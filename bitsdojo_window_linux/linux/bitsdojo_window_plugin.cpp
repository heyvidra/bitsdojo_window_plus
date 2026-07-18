// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
#include "include/bitsdojo_window_linux/bitsdojo_window_plugin.h"

#include "./window_impl.h"
#include "include/bitsdojo_window_linux/multi_window_manager.h"
#include <cmath>
#include <flutter_linux/flutter_linux.h>
#include <glib-object.h>
#include <gtk/gtk.h>

const char kChannelName[] = "bitsdojo/window";
const char kDragAppWindowMethod[] = "dragAppWindow";

struct _FlBitsdojoWindowPlugin {
  GObject parent_instance;

  FlPluginRegistrar *registrar;

  // Connection to Flutter engine.
  FlMethodChannel *channel;
};

G_DEFINE_TYPE(FlBitsdojoWindowPlugin, bitsdojo_window_plugin,
              g_object_get_type())

FlBitsdojoWindowPlugin *pluginInst = nullptr;

// Gets the top level window being controlled.
GtkWindow *get_window(FlBitsdojoWindowPlugin *self) {
  FlView *view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr)
    return nullptr;

  GtkWindow *window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  return window;
}

GtkWindow *getAppWindowHandle() { return get_window(pluginInst); }

static FlMethodResponse *
start_window_drag_at_position(FlBitsdojoWindowPlugin *self, FlValue *args) {
  auto window = get_window(self);
  startWindowDrag(window);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

// Called when a method call is received from Flutter.
static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  FlBitsdojoWindowPlugin *self = FL_BITSDOJO_WINDOW_PLUGIN(user_data);

  const gchar *method = fl_method_call_get_name(method_call);
  FlValue *args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, kDragAppWindowMethod) == 0) {
    response = start_window_drag_at_position(self, args);
  } else if (strcmp(method, "terminateApp") == 0) {
    auto window = get_window(self);
    if (window) {
      gtk_window_close(window);
    } else {
      g_application_quit(g_application_get_default());
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "openNewWindow") == 0) {
    if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      const char *name = nullptr;
      const char *arguments = nullptr;
      double width = 0;
      double height = 0;
      double x = 0;
      double y = 0;

      FlValue *name_val = fl_value_lookup_string(args, "name");
      if (name_val && fl_value_get_type(name_val) == FL_VALUE_TYPE_STRING) {
        name = fl_value_get_string(name_val);
      }

      FlValue *args_val = fl_value_lookup_string(args, "arguments");
      if (args_val && fl_value_get_type(args_val) == FL_VALUE_TYPE_STRING) {
        arguments = fl_value_get_string(args_val);
      }

      FlValue *width_val = fl_value_lookup_string(args, "width");
      if (width_val) {
        if (fl_value_get_type(width_val) == FL_VALUE_TYPE_FLOAT) {
          width = fl_value_get_float(width_val);
        } else if (fl_value_get_type(width_val) == FL_VALUE_TYPE_INT) {
          width = (double)fl_value_get_int(width_val);
        }
      }

      FlValue *height_val = fl_value_lookup_string(args, "height");
      if (height_val) {
        if (fl_value_get_type(height_val) == FL_VALUE_TYPE_FLOAT) {
          height = fl_value_get_float(height_val);
        } else if (fl_value_get_type(height_val) == FL_VALUE_TYPE_INT) {
          height = (double)fl_value_get_int(height_val);
        }
      }

      FlValue *x_val = fl_value_lookup_string(args, "x");
      if (x_val) {
        if (fl_value_get_type(x_val) == FL_VALUE_TYPE_FLOAT) {
          x = fl_value_get_float(x_val);
        } else if (fl_value_get_type(x_val) == FL_VALUE_TYPE_INT) {
          x = (double)fl_value_get_int(x_val);
        }
      }

      FlValue *y_val = fl_value_lookup_string(args, "y");
      if (y_val) {
        if (fl_value_get_type(y_val) == FL_VALUE_TYPE_FLOAT) {
          y = fl_value_get_float(y_val);
        } else if (fl_value_get_type(y_val) == FL_VALUE_TYPE_INT) {
          y = (double)fl_value_get_int(y_val);
        }
      }

      MultiWindowManager::GetInstance().OpenNewWindow(name, arguments, width,
                                                      height, x, y);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (strcmp(method, "setAlwaysOnTop") == 0) {
    if (fl_value_get_type(args) == FL_VALUE_TYPE_BOOL) {
      auto bdw = bitsdojo_window_from(get_window(self));
      bdw->setAlwaysOnTop(fl_value_get_bool(args));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else if (strcmp(method, "setWindowTitleBarButtonVisibility") == 0) {
    if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue *button_val = fl_value_lookup_string(args, "button");
      FlValue *visible_val = fl_value_lookup_string(args, "visible");
      if (button_val && visible_val) {
        auto bdw = bitsdojo_window_from(get_window(self));
        bdw->setWindowTitleBarButtonVisibility(fl_value_get_int(button_val),
                                               fl_value_get_bool(visible_val));
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
      }
    }
  } else if (strcmp(method, "setBackgroundEffect") == 0) {
    if (fl_value_get_type(args) == FL_VALUE_TYPE_INT) {
      auto bdw = bitsdojo_window_from(get_window(self));
      bdw->setBackgroundEffect(fl_value_get_int(args));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error))
    g_warning("Failed to send method call response: %s", error->message);
}

static void bitsdojo_window_plugin_dispose(GObject *object) {
  FlBitsdojoWindowPlugin *self = FL_BITSDOJO_WINDOW_PLUGIN(object);

  g_clear_object(&self->registrar);
  g_clear_object(&self->channel);

  G_OBJECT_CLASS(bitsdojo_window_plugin_parent_class)->dispose(object);
}

static void
bitsdojo_window_plugin_class_init(FlBitsdojoWindowPluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = bitsdojo_window_plugin_dispose;
}

static void bitsdojo_window_plugin_init(FlBitsdojoWindowPlugin *self) {
  pluginInst = self;
}

FlBitsdojoWindowPlugin *
bitsdojo_window_plugin_new(FlPluginRegistrar *registrar) {
  FlBitsdojoWindowPlugin *self = FL_BITSDOJO_WINDOW_PLUGIN(
      g_object_new(bitsdojo_window_plugin_get_type(), nullptr));

  self->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb,
                                            g_object_ref(self), g_object_unref);

  return self;
}

void bitsdojo_window_plugin_register_with_registrar(
    FlPluginRegistrar *registrar) {
  FlBitsdojoWindowPlugin *plugin = bitsdojo_window_plugin_new(registrar);
  FlView *view = fl_plugin_registrar_get_view(plugin->registrar);
  enhanceFlutterView(GTK_WIDGET(view));
  g_object_unref(plugin);
}

TOnOpenNewWindowCallback onOpenNewWindowCallback = nullptr;

void bitsdojo_window_set_on_open_new_window(TOnOpenNewWindowCallback callback) {
  onOpenNewWindowCallback = callback;
}

void bitsdojo_window_update_arguments(const char *arguments) {
  if (pluginInst == nullptr || pluginInst->channel == nullptr)
    return;
  g_autoptr(FlValue) args = fl_value_new_string(arguments);
  fl_method_channel_invoke_method(pluginInst->channel, "updateArguments", args,
                                  nullptr, nullptr, nullptr);
}

void bitsdojo_window_set_dart_entrypoint_arguments(char **arguments) {
  MultiWindowManager::GetInstance().SetDartEntrypointArguments(arguments);
}

#include <signal.h>
#include <sys/prctl.h>

void bitsdojo_window_configure_from_environment(GtkWindow *window) {
  if (!window)
    return;

  const char *w_str = getenv("BDW_WIDTH");
  const char *h_str = getenv("BDW_HEIGHT");
  const char *x_str = getenv("BDW_X");
  const char *y_str = getenv("BDW_Y");

  int width = (w_str && atoi(w_str) > 0) ? atoi(w_str) : 800;
  int height = (h_str && atoi(h_str) > 0) ? atoi(h_str) : 600;

  gtk_window_set_default_size(window, width, height);

  if (x_str && y_str) {
    gtk_window_move(window, atoi(x_str), atoi(y_str));
  }

  const char *depth_str = getenv("BDW_DEPTH");
  if (depth_str && atoi(depth_str) > 0) {
    // Child process: setup death signal so we exit when parent dies
    prctl(PR_SET_PDEATHSIG, SIGTERM);
  }
}
