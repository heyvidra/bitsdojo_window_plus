#ifndef _BDW_WINDOW_IMPL_
#define _BDW_WINDOW_IMPL_

void startWindowDrag(GtkWindow* window);
void enhanceFlutterView(GtkWidget* flutterView);

// Wire codes for the `windowEvent` channel message. Order must match
// WindowEventCode in
// bitsdojo_window_platform_interface/lib/window_event.dart.
enum BdwWindowEventCode {
  kBdwWindowFocused = 0,
  kBdwWindowBlurred = 1,
  kBdwWindowMoved = 2,
  kBdwWindowResized = 3,
  kBdwWindowMinimized = 4,
  kBdwWindowMaximized = 5,
  kBdwWindowRestored = 6,
};

// Forwards a window event to this engine's Dart side. Defined in
// bitsdojo_window_plugin.cpp, where the channel lives; declared here because
// that file and window_impl.cpp are the only two that need it, and both include
// this header — so the two signatures cannot drift.
//
// `a` and `b` carry the payload for moved (x, y) and resized (width, height),
// and are ignored for the rest. No window handle: a Linux secondary window is
// its own process, so an engine only ever reports its own window.
void bdwEmitWindowEvent(int code, double a, double b);

#endif  //_BDW_WINDOW_IMPL_
