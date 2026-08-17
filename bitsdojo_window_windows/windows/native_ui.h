#ifndef BITSDOJO_WINDOW_NATIVE_UI_H_
#define BITSDOJO_WINDOW_NATIVE_UI_H_

#include <windows.h>

#include <flutter/encodable_value.h>

#include <string>

namespace bitsdojo_native_ui {

// Shows a message box owned by `owner`, so it is window-modal rather than
// freezing the whole app. Returns the index of the pressed button, or -1 when
// the box was dismissed without one.
int ShowAlert(HWND owner, const flutter::EncodableMap& args);

// Pops up a menu over `owner` and returns once it closes, with the id of the
// picked item or an empty string when dismissed. `view` is the Flutter child
// window - the one whose client area the `x`/`y` in `args` are relative to.
std::string ShowMenu(HWND owner, HWND view, const flutter::EncodableMap& args);

// Every attached monitor, as maps matching Display.fromMap on the Dart side.
// Geometry is converted from physical pixels to the logical units Dart uses.
flutter::EncodableList GetDisplays();

}  // namespace bitsdojo_native_ui

#endif  // BITSDOJO_WINDOW_NATIVE_UI_H_
