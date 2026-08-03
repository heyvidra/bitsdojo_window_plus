import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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
  Listenable get changes => _changes;

  /// For platform implementations: signals [changes] listeners that this
  /// window's identity or arguments were updated.
  void notifyWindowChanged() => _changes.notify();

  int? get handle;
  double get scaleFactor;
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

enum DesktopWindowButton {
  close,
  minimize,
  zoom,
}
