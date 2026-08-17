import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'window_event.dart';

class _WindowChangeNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class DesktopWindowCapabilities {
  const DesktopWindowCapabilities({
    this.supportsBackgroundEffects = false,
    this.supportsTitleBarButtonVisibility = false,
    this.supportsTitleBarButtonOffset = false,
  });

  final bool supportsBackgroundEffects;
  final bool supportsTitleBarButtonVisibility;
  final bool supportsTitleBarButtonOffset;
}

enum WindowEffect {
  disabled,
  transparent,
  acrylic,
  mica,
  tabbed,
}

abstract class DesktopWindow {
  DesktopWindow();

  final _WindowChangeNotifier _changes = _WindowChangeNotifier();

  /// Notifies whenever this window's identity or arguments change — e.g.
  /// when the native `windowReady` message delivers name/arguments after
  /// engine startup, or `updateArguments` targets an existing named window.
  /// Multi-listener alternative to the single-slot [onArgumentsChanged].
  ///
  /// Platform implementations currently fire this only on the engine's own
  /// `appWindow`; proxy instances from `getWindowForHandle` expose the
  /// Listenable but receive no notifications.
  Listenable get changes => _changes;

  /// For platform implementations: signals [changes] listeners that this
  /// window's identity or arguments were updated.
  void notifyWindowChanged() => _changes.notify();

  final StreamController<WindowEvent> _events =
      StreamController<WindowEvent>.broadcast();

  /// What the OS did to this window: focus, move, resize, minimize, maximize,
  /// restore. Broadcast, so several listeners can subscribe, and events that
  /// arrive with nobody listening are dropped rather than buffered.
  ///
  /// Never closed — a window object lives as long as its engine — so there is
  /// nothing to dispose. Cancel your own subscriptions as usual.
  ///
  /// Closing is not here on purpose: use [onClose] to veto a close, and
  /// top-level `onWindowClosed` to hear about other windows closing.
  Stream<WindowEvent> get events => _events.stream;

  /// For platform implementations: publishes an event to [events].
  void emitWindowEvent(WindowEvent event) => _events.add(event);

  int? get handle;

  /// What the DISPLAY reports about itself: DPI/96 on Windows, the Retina
  /// backing scale on macOS.
  ///
  /// A property of the screen, NOT a conversion factor — the two only coincide
  /// on Windows. Converting coordinates with this turns every point on a
  /// Retina Mac into half of itself. Use [coordinateScale] for that.
  double get scaleFactor;

  /// Multiply a LOGICAL coordinate by this to get what [rect], [position] and
  /// `animateTo` actually speak on this platform. Divide to come back.
  ///
  /// 1.0 on macOS and Linux, where those APIs are already in points, and
  /// DPI/96 on Windows, where they are raw device pixels. That split is the
  /// whole reason this exists apart from [scaleFactor]: every caller needing
  /// it was re-deriving it — one inside this package, one in an app on top of
  /// it — and each had to know for itself which platforms lie.
  ///
  /// Measured rather than assumed: [size] is logical everywhere and [rect] is
  /// not, so their ratio IS this number. Cross-checked against [scaleFactor],
  /// which is exact where the ratio is a rounded division. Falls back to 1.0
  /// whenever the window cannot be measured — the answer that leaves
  /// coordinates untouched.
  double get coordinateScale {
    final logicalWidth = size.width;
    final physicalWidth = rect.width;
    if (logicalWidth <= 0 || physicalWidth <= 0) return 1.0;

    final inferred = physicalWidth / logicalWidth;
    if (!inferred.isFinite || inferred <= 0) return 1.0;
    if ((inferred - 1).abs() < 0.01) return 1.0;

    final reported = scaleFactor;
    if (reported > 0 && (inferred - reported).abs() < 0.05) return reported;
    return inferred;
  }

  DesktopWindowCapabilities get capabilities =>
      const DesktopWindowCapabilities();

  Rect get rect;
  set rect(Rect newRect);

  Offset get position;
  set position(Offset newPosition);

  Size get size;
  set size(Size newSize);

  set minSize(Size? newSize);
  set maxSize(Size? newSize);

  Size get screenSize;
  Size get workingScreenSize;
  Rect get workingScreenRect;

  Alignment? get alignment;
  set alignment(Alignment? newAlignment);

  set title(String newTitle);

  @Deprecated("use isVisible instead")
  bool get visible;
  bool get isVisible;
  @Deprecated("use show()/hide() instead")
  set visible(bool isVisible);
  void show();
  void hide();
  void close();
  void minimize();
  void maximize();
  void maximizeOrRestore();
  void toggleFullScreen();
  void restore();

  void startDragging();

  bool get alwaysOnTop;
  set alwaysOnTop(bool onTop);

  bool get hasShadow;
  set hasShadow(bool value);

  Size get titleBarButtonSize;

  double get titleBarHeight;
  set titleBarHeight(double height);

  double get borderSize;
  bool get isMaximized;
  VoidCallback? get onClose;
  set onClose(VoidCallback? callback);
  VoidCallback? get onArgumentsChanged;
  set onArgumentsChanged(VoidCallback? callback);
  set backgroundEffect(WindowEffect effect);
  bool get isMainWindow;
  int get depth;
  String? get name;
  Map<String, dynamic>? get arguments;
  Future<void> openNewWindow({
    String? name,
    Size? size,
    Offset? position,
    Map<String, dynamic>? arguments,
  });

  void setWindowTitleBarButtonVisibility(
      DesktopWindowButton button, bool visible) {}
  void setWindowTitleBarButtonOffset(
      DesktopWindowButton button, Offset offset) {}
}

/// A title-bar button.
///
/// Crosses the channel as `button.index`, and macOS casts that integer straight
/// into AppKit's `NSWindowButton` (see `titlebar_button_manager.mm`) — a foreign
/// ABI this package does not control, where 0/1/2 are close/miniaturize/zoom.
/// So: **append only**. Reordering or inserting a value silently retargets which
/// native button gets hidden or moved, with nothing in Dart to catch it. The
/// ordinals are pinned by a test in the platform interface package.
enum DesktopWindowButton {
  close,
  minimize,
  zoom,
}
