#include <bitsdojo_window_linux/bitsdojo_window_plugin.h>
#include <glib.h>
#include <stdio.h>
#include <unistd.h>

#include "flutter/generated_plugin_registrant.h"
#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

struct _MyApplication {
  GtkApplication parent_instance;
  char **dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication *self, FlView *view) {
  g_print("*** [%d] first_frame_cb called! Showing window... ***\n", getpid());
  fflush(stdout);
  GtkWindow *window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  gtk_widget_show(GTK_WIDGET(window));
  gtk_window_present(window);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication *application) {
  MyApplication *self = MY_APPLICATION(application);

  GList *windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows != NULL) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }

  GtkWindow *window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen *screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar *wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar *header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "example");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "example");
  }

  auto bdw = bitsdojo_window_from(window);
  bdw->setCustomFrame(true);
  bitsdojo_window_set_dart_entrypoint_arguments(self->dart_entrypoint_arguments);
  bitsdojo_window_configure_from_environment(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();

  if (self->dart_entrypoint_arguments) {
    fl_dart_project_set_dart_entrypoint_arguments(
        project, self->dart_entrypoint_arguments);
  }

  FlView *view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#F6FBFA");
  fl_view_set_background_color(view, &background_color);

  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_show(GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_realize(GTK_WIDGET(view));
  gtk_widget_grab_focus(GTK_WIDGET(view));

  gtk_widget_realize(GTK_WIDGET(window));
}

static void my_application_dispose(GObject *object) {
  MyApplication *self = MY_APPLICATION(object);
  g_strfreev(self->dart_entrypoint_arguments);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static int
my_application_command_line(GApplication *application,
                            GApplicationCommandLine *command_line) {
  const bool had_window_before_activate =
      gtk_application_get_windows(GTK_APPLICATION(application)) != nullptr;

  g_application_activate(application);

  const gchar *const *envp = g_application_command_line_get_environ(command_line);
  const char *args = g_environ_getenv((gchar **)envp, "BDW_ARGS");
  if (args) {
    bitsdojo_window_update_arguments(args);
  }

  GtkWindow *window =
      gtk_application_get_active_window(GTK_APPLICATION(application));
  if (had_window_before_activate && window) {
    gtk_window_present(window);
  }

  return 0;
}

extern "C" gboolean my_application_local_command_line(GApplication *application,
                                                      gchar ***arguments,
                                                      int *exit_status) {
  MyApplication *self = MY_APPLICATION(application);

  if (self->dart_entrypoint_arguments) {
    g_strfreev(self->dart_entrypoint_arguments);
  }
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  return FALSE;
}

static void my_application_class_init(MyApplicationClass *klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication *self) {
}

MyApplication *my_application_new(int argc, char **argv) {
  const char *depthStr = getenv("BDW_DEPTH");
  int depth = depthStr ? atoi(depthStr) : 0;
  const char *name = getenv("BDW_NAME");

  MyApplication *self;
  GApplicationFlags flags = G_APPLICATION_DEFAULT_FLAGS;

  char appId[128];
  if (depth == 0) {
    sprintf(appId, "com.example.example");
  } else {
    if (name) {
      sprintf(appId, "com.example.example.n.%s", name);
      flags = (GApplicationFlags)(G_APPLICATION_HANDLES_COMMAND_LINE |
                                   G_APPLICATION_SEND_ENVIRONMENT);
    } else {
      sprintf(appId, "com.example.example.p%d", getpid());
      flags = G_APPLICATION_NON_UNIQUE;
    }
  }

  self = MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", appId, "flags", flags,
                                     nullptr));

  if (argc > 1) {
    self->dart_entrypoint_arguments = g_strdupv(argv + 1);
  }

  return self;
}
