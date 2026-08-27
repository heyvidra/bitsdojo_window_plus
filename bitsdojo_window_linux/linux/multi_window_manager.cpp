#include "include/bitsdojo_window_linux/multi_window_manager.h"
#include <glib/gstdio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <vector>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

MultiWindowManager &MultiWindowManager::GetInstance() {
  static MultiWindowManager instance;
  return instance;
}

// Attached to every child watch. The refs keep both pointers instance-valid
// even if the parent window (and with it the spawning plugin) is destroyed
// while the child process is still running.
struct SpawnWatchData {
  // Owned copy of the child's window name; null only for a defensively
  // handled unnamed spawn (Dart always names windows now), which cannot be
  // routed and therefore is not broadcast.
  gchar *name;
  // Owned path of the dialog result file, or null for non-dialog spawns.
  // The file only exists if the dialog's Dart wrote a result before closing.
  gchar *result_file;
  // Ref'd modal parent to re-enable, or null. The ref only guarantees the
  // pointer is valid — ReleaseModalParent checks liveness before poking it.
  GtkWindow *parent;
  // Ref'd channel of the spawning plugin. Holding a strong ref means the
  // object outlives its plugin, and that is enough for safety: the channel
  // holds its messenger, which holds the engine only weakly, so invoking on
  // a channel whose engine already died is a silent no-op — never a crash.
  FlMethodChannel *channel;
};

// Reaps a child window process when it exits. Without this, every closed
// child window stays as a <defunct> zombie for the parent's lifetime
// (G_SPAWN_DO_NOT_REAP_CHILD disables GLib's automatic reaping).
// Apps that also spawn processes via dart:io may see a benign GLib ECHILD
// warning here: the Dart VM's exit-code handler waits on any child and can
// reap ours first (pidfd-based watches on GLib >= 2.64 avoid the race).
static void OnChildWindowExited(GPid pid, gint /*status*/,
                                gpointer user_data) {
  g_spawn_close_pid(pid);
  SpawnWatchData *data = static_cast<SpawnWatchData *>(user_data);
  if (data == nullptr)
    return;

  if (data->parent != nullptr) {
    MultiWindowManager::GetInstance().ReleaseModalParent(data->parent);
    g_object_unref(data->parent);
  }

  // The dialog result crosses processes as a file: the child's Dart wrote it
  // (if closeWithResult ran), and this exit watch is the first moment the
  // parent knows the write is final. The file was pre-created empty by
  // g_mkstemp, so empty = the dialog never set a result. Unlink either way.
  g_autofree gchar *result = nullptr;
  if (data->result_file != nullptr) {
    gsize result_len = 0;
    g_file_get_contents(data->result_file, &result, &result_len, nullptr);
    g_unlink(data->result_file);
    // Invalid UTF-8 (a dialog killed mid-write) must never reach the method
    // codec: the Dart side would fail to decode the whole windowClosed
    // message and the awaiting openDialog would hang forever, instead of
    // the null the hub's own json guard was built to deliver.
    if (result != nullptr &&
        (result_len == 0 || !g_utf8_validate(result, result_len, nullptr))) {
      g_free(result);
      result = nullptr;
    }
  }

  // Linux's only windowClosed delivery: one process per window means there is
  // no broadcast bus, so the close is reported into the engine that spawned
  // the child — it fires for every window THIS process spawned (dialog or
  // not), and that is the documented ceiling of the one-process-per-window
  // model.
  if (data->channel != nullptr && data->name != nullptr) {
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "name", fl_value_new_string(data->name));
    if (result != nullptr) {
      fl_value_set_string_take(args, "result", fl_value_new_string(result));
    }
    fl_method_channel_invoke_method(data->channel, "windowClosed", args,
                                    nullptr, nullptr, nullptr);
  }

  if (data->channel != nullptr) {
    g_object_unref(data->channel);
  }
  g_free(data->name);
  g_free(data->result_file);
  delete data;
}

void MultiWindowManager::ReleaseModalParent(GtkWindow *parent) {
  auto it = modal_counts_.find(parent);
  if (it == modal_counts_.end())
    return;
  it->second--;
  if (it->second > 0)
    return;
  modal_counts_.erase(it);
  // The watch's ref only guarantees the pointer is valid — the window itself
  // may have been destroyed while the dialog was open, so don't poke a dead
  // window.
  //
  // Re-enable input only; focus return is the WM's job (WM_TRANSIENT_FOR
  // usually gets it right on X11). Presenting the parent here would be
  // actively wrong on the named-REUSE path: that spawn is a short-lived
  // forwarder whose exit lands right after the reused window was presented,
  // and a present() from this watch would steal the focus back off it.
  if (GTK_IS_WINDOW(parent) && gtk_widget_get_realized(GTK_WIDGET(parent))) {
    gtk_widget_set_sensitive(GTK_WIDGET(parent), TRUE);
  }
}

MultiWindowManager::MultiWindowManager() {}

MultiWindowManager::~MultiWindowManager() {
  if (dart_entrypoint_arguments_) {
    g_strfreev(dart_entrypoint_arguments_);
  }
}

void MultiWindowManager::SetDartEntrypointArguments(char **args) {
  if (dart_entrypoint_arguments_) {
    g_strfreev(dart_entrypoint_arguments_);
  }
  dart_entrypoint_arguments_ = g_strdupv(args);
}

void MultiWindowManager::OpenNewWindow(const char *name, const char *arguments,
                                       double width, double height, double x,
                                       double y, bool has_position,
                                       const char *modality, GtkWindow *parent,
                                       FlMethodChannel *notify_channel) {
  char exePath[1024];
  ssize_t len = readlink("/proc/self/exe", exePath, sizeof(exePath) - 1);
  if (len != -1) {
    exePath[len] = '\0';
  } else {
    g_warning("[MultiWindowManager] Could not determine executable path");
    return;
  }

  // Construct arguments for the new process
  GPtrArray *argv = g_ptr_array_new_with_free_func(g_free);
  g_ptr_array_add(argv, g_strdup(exePath));

  // Pass along the original arguments
  if (dart_entrypoint_arguments_) {
    int count = g_strv_length(dart_entrypoint_arguments_);
    for (int i = 0; i < count; i++) {
      g_ptr_array_add(argv, g_strdup(dart_entrypoint_arguments_[i]));
    }
  }
  g_ptr_array_add(argv, NULL);

  // Set environment variables for the child process
  g_auto(GStrv) envp = g_get_environ();

  // Strip FLUTTER_ENGINE_SWITCH environment variables
  for (int i = 1; i <= 20; i++) {
    char key[64];
    sprintf(key, "FLUTTER_ENGINE_SWITCH_%d", i);
    envp = g_environ_unsetenv(envp, key);
  }
  envp = g_environ_unsetenv(envp, "FLUTTER_ENGINE_SWITCHES");

  // Scrub inherited window identity/geometry: a child window process carries
  // its own BDW_* values, so an unnamed/unpositioned grandchild would
  // otherwise inherit them — wrong route (stale BDW_NAME/BDW_ARGS) and a
  // stale position/size. Same for modality: a window spawned BY a dialog must
  // not itself become a dialog of the dialog's parent.
  envp = g_environ_unsetenv(envp, "BDW_NAME");
  envp = g_environ_unsetenv(envp, "BDW_ARGS");
  envp = g_environ_unsetenv(envp, "BDW_X");
  envp = g_environ_unsetenv(envp, "BDW_Y");
  envp = g_environ_unsetenv(envp, "BDW_WIDTH");
  envp = g_environ_unsetenv(envp, "BDW_HEIGHT");
  envp = g_environ_unsetenv(envp, "BDW_MODALITY");
  envp = g_environ_unsetenv(envp, "BDW_PARENT_XID");
  envp = g_environ_unsetenv(envp, "BDW_RESULT_FILE");

  const char *currentDepthStr = g_environ_getenv(envp, "BDW_DEPTH");
  int currentDepth = currentDepthStr ? atoi(currentDepthStr) : 0;
  char depthStr[32];
  snprintf(depthStr, sizeof(depthStr), "%d", currentDepth + 1);
  envp = g_environ_setenv(envp, "BDW_DEPTH", depthStr, TRUE);

  if (name) {
    envp = g_environ_setenv(envp, "BDW_NAME", name, TRUE);
  }
  if (arguments) {
    envp = g_environ_setenv(envp, "BDW_ARGS", arguments, TRUE);
  }

  char widthStr[32], heightStr[32], xStr[32], yStr[32];
  if (width > 0 && height > 0) {
    snprintf(widthStr, sizeof(widthStr), "%.f", width);
    snprintf(heightStr, sizeof(heightStr), "%.f", height);
    envp = g_environ_setenv(envp, "BDW_WIDTH", widthStr, TRUE);
    envp = g_environ_setenv(envp, "BDW_HEIGHT", heightStr, TRUE);
  }
  if (has_position) {
    snprintf(xStr, sizeof(xStr), "%.f", x);
    snprintf(yStr, sizeof(yStr), "%.f", y);
    envp = g_environ_setenv(envp, "BDW_X", xStr, TRUE);
    envp = g_environ_setenv(envp, "BDW_Y", yStr, TRUE);
  }

  // Cross-process parent/dialog link, deliberately degraded to what separate
  // processes allow: the input block (insensitive parent) works on every
  // backend; dialog stacking/transient-for only reaches the WM on X11 —
  // Wayland has no cross-process parenting primitive, so BDW_PARENT_XID is
  // simply omitted there. If this process dies before the dialog does, no
  // bookkeeping here tears the dialog down — the child's own
  // PR_SET_PDEATHSIG handles that.
  bool is_modal = modality != nullptr && strcmp(modality, "modal") == 0;
  bool is_modeless = modality != nullptr && strcmp(modality, "modeless") == 0;
  // Where a dialog result (closeWithResult) crosses the process boundary:
  // the child's Dart writes the json to this file, and the parent's exit
  // watch reads it back once the process is gone. Owned by this function
  // until the spawn succeeds, then by the watch data.
  gchar *result_file = nullptr;
  if (is_modal || is_modeless) {
    // g_mkstemp, not a hand-minted name: the file is created HERE, 0600 and
    // O_EXCL, so a hostile pre-created file or symlink at a guessable path in
    // world-writable /tmp can neither feed a fake result into openDialog nor
    // redirect the dialog's write (CWE-377). Pre-creating also means a stale
    // file from a crashed previous incarnation can never be read back: this
    // path is always a fresh empty file. The exit watch unlinks it
    // unconditionally, and empty content reads as "no result".
    result_file = g_build_filename(g_get_tmp_dir(), "bdw_result_XXXXXX", NULL);
    int result_fd = g_mkstemp(result_file);
    if (result_fd == -1) {
      // No safe file, no result channel: the dialog still opens and its
      // close simply reads as null on the awaiting side.
      g_free(result_file);
      result_file = nullptr;
    } else {
      close(result_fd);
      envp = g_environ_setenv(envp, "BDW_RESULT_FILE", result_file, TRUE);
    }
    envp = g_environ_setenv(envp, "BDW_MODALITY",
                            is_modal ? "modal" : "modeless", TRUE);
#ifdef GDK_WINDOWING_X11
    if (parent != nullptr) {
      GdkWindow *parent_gdk = gtk_widget_get_window(GTK_WIDGET(parent));
      if (parent_gdk != nullptr && GDK_IS_X11_WINDOW(parent_gdk)) {
        char xidStr[32];
        snprintf(xidStr, sizeof(xidStr), "%lu",
                 (unsigned long)gdk_x11_window_get_xid(parent_gdk));
        envp = g_environ_setenv(envp, "BDW_PARENT_XID", xidStr, TRUE);
      }
    }
#endif
  }

  // Opt-in workaround for boards whose GL drivers crash child windows (e.g.
  // some ARM64 systems missing HW acceleration libs): export
  // BDW_CHILD_WINDOW_SOFTWARE_RENDERING=1 in the parent environment to force
  // software GL + the X11 backend for spawned windows. Never forced by
  // default — software rendering is a large performance hit for everyone
  // else.
  const char *forceSoftware =
      g_environ_getenv(envp, "BDW_CHILD_WINDOW_SOFTWARE_RENDERING");
  if (forceSoftware && strcmp(forceSoftware, "1") == 0) {
    envp = g_environ_setenv(envp, "LIBGL_ALWAYS_SOFTWARE", "1", TRUE);
    envp = g_environ_setenv(envp, "GDK_BACKEND", "x11", TRUE);
  }
  const char *disableA11y =
      g_environ_getenv(envp, "BDW_DISABLE_CHILD_WINDOW_ACCESSIBILITY");
  if (disableA11y && strcmp(disableA11y, "1") == 0) {
    envp = g_environ_setenv(envp, "NO_AT_BRIDGE", "1", TRUE);
    envp = g_environ_setenv(envp, "GTK_A11Y", "none", TRUE);
    envp = g_environ_setenv(envp, "ACCESSIBILITY_ENABLED", "0", TRUE);
    envp = g_environ_setenv(envp, "QT_ACCESSIBILITY", "0", TRUE);
    envp = g_environ_unsetenv(envp, "GTK_MODULES");
  }

  // Block input before the dialog process even maps — a click in the gap
  // between spawn and map must not reach the parent. Named-window REUSE is
  // resolved by GApplication app-id uniqueness inside the spawned process:
  // when the name already has a window, the spawn is a short-lived forwarder
  // that presents the existing window and exits — so modality is deliberately
  // ignored on that path, the exit watch below undoing the block right away.
  bool parent_disabled_here = false;
  if (is_modal && parent != nullptr) {
    gtk_widget_set_sensitive(GTK_WIDGET(parent), FALSE);
    parent_disabled_here = true;
  }

  GError *error = NULL;
  GPid child_pid;
  if (!g_spawn_async(NULL, (gchar **)argv->pdata, envp,
                     G_SPAWN_DO_NOT_REAP_CHILD, NULL, NULL, &child_pid,
                     &error)) {
    g_warning("[MultiWindowManager] Failed to spawn child process: %s",
              error->message);
    g_error_free(error);
    g_free(result_file);
    // Only re-enable when no earlier modal dialog still holds this parent.
    if (parent_disabled_here &&
        modal_counts_.find(parent) == modal_counts_.end()) {
      gtk_widget_set_sensitive(GTK_WIDGET(parent), TRUE);
    }
  } else {
    GtkWindow *modal_parent = nullptr;
    if (parent_disabled_here) {
      modal_counts_[parent]++;
      modal_parent = GTK_WINDOW(g_object_ref(parent));
    }
    // Watch data for every spawn, not just modal ones: the exit watch is
    // also the parent's only way to learn that the child window closed (and
    // to collect a dialog result), so the channel rides along even when
    // there is no modal parent to re-enable.
    SpawnWatchData *watch_data = new SpawnWatchData{
        g_strdup(name), result_file, modal_parent,
        notify_channel != nullptr
            ? FL_METHOD_CHANNEL(g_object_ref(notify_channel))
            : nullptr};
    g_child_watch_add(child_pid, OnChildWindowExited, watch_data);
  }
  g_ptr_array_unref(argv);
}
