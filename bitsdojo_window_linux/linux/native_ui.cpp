#include "./native_ui.h"

namespace {

const char *lookup_string(FlValue *map, const char *key) {
  FlValue *value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

bool lookup_bool(FlValue *map, const char *key, bool fallback) {
  FlValue *value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

bool lookup_double(FlValue *map, const char *key, double *out) {
  FlValue *value = fl_value_lookup_string(map, key);
  if (value == nullptr)
    return false;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    *out = fl_value_get_float(value);
    return true;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    *out = (double)fl_value_get_int(value);
    return true;
  }
  return false;
}

// One popup's state: the id picked so far and the nested loop that keeps
// `bdw_show_menu` blocked until the menu is done.
struct MenuPick {
  char *id;
  GMainLoop *loop;
};

void on_item_activate(GtkMenuItem *item, gpointer user_data) {
  MenuPick *pick = static_cast<MenuPick *>(user_data);
  const char *id =
      static_cast<const char *>(g_object_get_data(G_OBJECT(item), "bdw-id"));
  if (id != nullptr) {
    g_free(pick->id);
    pick->id = g_strdup(id);
  }
}

gboolean quit_menu_loop(gpointer user_data) {
  MenuPick *pick = static_cast<MenuPick *>(user_data);
  if (pick->loop != nullptr && g_main_loop_is_running(pick->loop)) {
    g_main_loop_quit(pick->loop);
  }
  return G_SOURCE_REMOVE;
}

void on_menu_deactivate(GtkMenuShell *shell, gpointer user_data) {
  // GTK emits "deactivate" on the shell BEFORE the picked item's "activate",
  // so quitting here directly would return before the id is recorded. Handing
  // the quit to the idle queue lets the activation land first.
  g_idle_add(quit_menu_loop, user_data);
}

void build_menu(GtkWidget *menu, FlValue *items, MenuPick *pick) {
  size_t count = fl_value_get_length(items);
  for (size_t i = 0; i < count; i++) {
    FlValue *entry = fl_value_get_list_value(items, i);
    if (fl_value_get_type(entry) != FL_VALUE_TYPE_MAP)
      continue;

    const char *id = lookup_string(entry, "id");
    if (id == nullptr) {
      gtk_menu_shell_append(GTK_MENU_SHELL(menu),
                            gtk_separator_menu_item_new());
      continue;
    }

    const char *label = lookup_string(entry, "label");
    if (label == nullptr)
      label = "";

    GtkWidget *item;
    if (lookup_bool(entry, "checked", false)) {
      item = gtk_check_menu_item_new_with_label(label);
      gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(item), TRUE);
    } else {
      item = gtk_menu_item_new_with_label(label);
    }
    if (!lookup_bool(entry, "enabled", true)) {
      gtk_widget_set_sensitive(item, FALSE);
    }

    FlValue *submenu = fl_value_lookup_string(entry, "submenu");
    if (submenu != nullptr &&
        fl_value_get_type(submenu) == FL_VALUE_TYPE_LIST) {
      // An item that opens a submenu is never picked itself, so it gets no
      // id and no activate handler.
      GtkWidget *child = gtk_menu_new();
      build_menu(child, submenu, pick);
      gtk_menu_item_set_submenu(GTK_MENU_ITEM(item), child);
    } else {
      g_object_set_data_full(G_OBJECT(item), "bdw-id", g_strdup(id), g_free);
      g_signal_connect(item, "activate", G_CALLBACK(on_item_activate), pick);
    }
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  }
}

} // namespace

int bdw_show_alert(GtkWindow *parent, FlValue *args) {
  const char *title = lookup_string(args, "title");
  const char *message = lookup_string(args, "message");

  GtkMessageType type = GTK_MESSAGE_INFO;
  FlValue *style = fl_value_lookup_string(args, "style");
  if (style != nullptr && fl_value_get_type(style) == FL_VALUE_TYPE_INT) {
    int64_t value = fl_value_get_int(style);
    if (value == 1)
      type = GTK_MESSAGE_WARNING;
    else if (value == 2)
      type = GTK_MESSAGE_ERROR;
  }

  GtkWidget *dialog = gtk_message_dialog_new(
      parent,
      GtkDialogFlags(GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT), type,
      GTK_BUTTONS_NONE, "%s", title != nullptr ? title : "");
  if (message != nullptr && message[0] != '\0') {
    gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog), "%s",
                                             message);
  }

  // Response ids are the caller's button indices, so gtk_dialog_run hands back
  // the index directly. Anything negative is GTK's own (delete-event, Esc).
  FlValue *buttons = fl_value_lookup_string(args, "buttons");
  size_t count = buttons != nullptr &&
                         fl_value_get_type(buttons) == FL_VALUE_TYPE_LIST
                     ? fl_value_get_length(buttons)
                     : 0;
  if (count == 0) {
    gtk_dialog_add_button(GTK_DIALOG(dialog), "OK", 0);
  }
  for (size_t i = 0; i < count; i++) {
    FlValue *label = fl_value_get_list_value(buttons, i);
    gtk_dialog_add_button(
        GTK_DIALOG(dialog),
        fl_value_get_type(label) == FL_VALUE_TYPE_STRING
            ? fl_value_get_string(label)
            : "",
        (gint)i);
  }

  // buttons[0] is the affirmative one on every platform - NSAlert makes the
  // first button the default, MessageBoxW defaults to OK - so Return has to
  // pick it here too.
  gtk_dialog_set_default_response(GTK_DIALOG(dialog), 0);

  gint response = gtk_dialog_run(GTK_DIALOG(dialog));
  gtk_widget_destroy(dialog);
  return response < 0 ? -1 : (int)response;
}

char *bdw_show_menu(GtkWidget *view, FlValue *args) {
  FlValue *items = fl_value_lookup_string(args, "items");
  if (items == nullptr || fl_value_get_type(items) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(items) == 0) {
    // An empty menu never maps to a window, so it would never emit
    // "deactivate" and the loop below would never end.
    return nullptr;
  }

  MenuPick pick = {nullptr, nullptr};
  GtkWidget *menu = gtk_menu_new();
  build_menu(menu, items, &pick);
  gtk_widget_show_all(menu);

  pick.loop = g_main_loop_new(nullptr, FALSE);
  g_signal_connect(menu, "deactivate", G_CALLBACK(on_menu_deactivate), &pick);

  double x = 0;
  double y = 0;
  GdkWindow *view_window =
      view != nullptr ? gtk_widget_get_window(view) : nullptr;
  if (view_window != nullptr && lookup_double(args, "x", &x) &&
      lookup_double(args, "y", &y)) {
    // Flutter's logical pixels and GTK widget coordinates are the same unit
    // (the scale factor applies to both), so the offset passes through as-is.
    // The trigger event stays NULL: the right-click that asked for this menu
    // was consumed by Flutter, so GTK never saw a GdkEvent for it. GTK logs
    // "no trigger event for menu popup" and falls back to the pointer's
    // current grab, which is what we want anyway.
    GdkRectangle anchor = {(int)x, (int)y, 1, 1};
    gtk_menu_popup_at_rect(GTK_MENU(menu), view_window, &anchor,
                           GDK_GRAVITY_NORTH_WEST, GDK_GRAVITY_NORTH_WEST,
                           nullptr);
  } else {
    gtk_menu_popup_at_pointer(GTK_MENU(menu), nullptr);
  }

  g_main_loop_run(pick.loop);
  g_main_loop_unref(pick.loop);
  pick.loop = nullptr;
  gtk_widget_destroy(menu);
  return pick.id;
}
