#include "include/bitsdojo_window_linux/multi_window_manager.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <vector>

MultiWindowManager &MultiWindowManager::GetInstance() {
  static MultiWindowManager instance;
  return instance;
}

// Reaps a child window process when it exits. Without this, every closed
// child window stays as a <defunct> zombie for the parent's lifetime
// (G_SPAWN_DO_NOT_REAP_CHILD disables GLib's automatic reaping).
// Apps that also spawn processes via dart:io may see a benign GLib ECHILD
// warning here: the Dart VM's exit-code handler waits on any child and can
// reap ours first (pidfd-based watches on GLib >= 2.64 avoid the race).
static void OnChildWindowExited(GPid pid, gint /*status*/,
                                gpointer /*user_data*/) {
  g_spawn_close_pid(pid);
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
                                       double y, bool has_position) {
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
  // stale position/size.
  envp = g_environ_unsetenv(envp, "BDW_NAME");
  envp = g_environ_unsetenv(envp, "BDW_ARGS");
  envp = g_environ_unsetenv(envp, "BDW_X");
  envp = g_environ_unsetenv(envp, "BDW_Y");
  envp = g_environ_unsetenv(envp, "BDW_WIDTH");
  envp = g_environ_unsetenv(envp, "BDW_HEIGHT");

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

  GError *error = NULL;
  GPid child_pid;
  if (!g_spawn_async(NULL, (gchar **)argv->pdata, envp,
                     G_SPAWN_DO_NOT_REAP_CHILD, NULL, NULL, &child_pid,
                     &error)) {
    g_warning("[MultiWindowManager] Failed to spawn child process: %s",
              error->message);
    g_error_free(error);
  } else {
    g_child_watch_add(child_pid, OnChildWindowExited, NULL);
  }
  g_ptr_array_unref(argv);
}
