import 'dart:ui' show Offset, Size;

/// Something the OS did to a window, delivered on `DesktopWindow.events`.
///
/// Closing is deliberately absent: it already has two better-shaped APIs —
/// `DesktopWindow.onClose` can *veto* a close, and top-level `onWindowClosed`
/// reports another window's close to the engines that outlive it. An event on a
/// stream can do neither.
///
/// `sealed`, so a `switch` over the subtypes is checked for exhaustiveness and
/// adding an event here becomes a compile error at every call site that has to
/// handle it:
///
/// ```dart
/// appWindow.events.listen((event) {
///   switch (event) {
///     case WindowMoved(:final position): saveOrigin(position);
///     case WindowResized(:final size): saveSize(size);
///     case WindowFocused(): resume();
///     case WindowBlurred(): pause();
///     case WindowMinimized() || WindowMaximized() || WindowRestored(): break;
///   }
/// });
/// ```
sealed class WindowEvent {
  const WindowEvent();
}

/// The window became the active one.
class WindowFocused extends WindowEvent {
  const WindowFocused();
}

/// The window stopped being the active one.
class WindowBlurred extends WindowEvent {
  const WindowBlurred();
}

/// The window's top-left moved to [position] (logical pixels).
class WindowMoved extends WindowEvent {
  const WindowMoved(this.position);
  final Offset position;
}

/// The window's content area became [size] (logical pixels).
class WindowResized extends WindowEvent {
  const WindowResized(this.size);
  final Size size;
}

class WindowMinimized extends WindowEvent {
  const WindowMinimized();
}

/// Zoomed on macOS, maximized on Windows and Linux.
class WindowMaximized extends WindowEvent {
  const WindowMaximized();
}

/// Back to normal from minimized or maximized.
class WindowRestored extends WindowEvent {
  const WindowRestored();
}

/// Wire codes shared with the three native implementations. Kept as ints rather
/// than strings because every platform builds these in C/C++/Swift, where an
/// int switch is the cheapest thing to get right.
enum WindowEventCode {
  focused,
  blurred,
  moved,
  resized,
  minimized,
  maximized,
  restored,
}

/// Decodes a `windowEvent` channel message. Returns null for a code this
/// version of the Dart side doesn't know, so a newer native layer can add
/// events without breaking an older Dart side.
WindowEvent? decodeWindowEvent(Map<Object?, Object?> arguments) {
  final code = arguments['type'];
  if (code is! int || code < 0 || code >= WindowEventCode.values.length) {
    return null;
  }
  switch (WindowEventCode.values[code]) {
    case WindowEventCode.focused:
      return const WindowFocused();
    case WindowEventCode.blurred:
      return const WindowBlurred();
    case WindowEventCode.moved:
      final x = (arguments['x'] as num?)?.toDouble();
      final y = (arguments['y'] as num?)?.toDouble();
      if (x == null || y == null) return null;
      return WindowMoved(Offset(x, y));
    case WindowEventCode.resized:
      final width = (arguments['width'] as num?)?.toDouble();
      final height = (arguments['height'] as num?)?.toDouble();
      if (width == null || height == null) return null;
      return WindowResized(Size(width, height));
    case WindowEventCode.minimized:
      return const WindowMinimized();
    case WindowEventCode.maximized:
      return const WindowMaximized();
    case WindowEventCode.restored:
      return const WindowRestored();
  }
}
