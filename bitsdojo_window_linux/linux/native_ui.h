#ifndef BITSDOJO_WINDOW_NATIVE_UI_H_
#define BITSDOJO_WINDOW_NATIVE_UI_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Shows a GtkMessageDialog transient for `parent`, so the window manager keeps
// it over the window that asked for it. Blocks until answered and returns the
// index of the pressed button, or -1 when dismissed.
int bdw_show_alert(GtkWindow *parent, FlValue *args);

// Pops up a GtkMenu over `view` and blocks until it closes. Returns a newly
// allocated id of the picked item - free with g_free - or nullptr when the menu
// was dismissed.
char *bdw_show_menu(GtkWidget *view, FlValue *args);

#endif // BITSDOJO_WINDOW_NATIVE_UI_H_
