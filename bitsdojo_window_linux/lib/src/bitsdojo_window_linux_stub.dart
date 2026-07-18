import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:flutter/painting.dart';

class BitsdojoWindowLinux extends BitsdojoWindowPlatform {
  BitsdojoWindowLinux() {
    assert(false);
  }

  @override
  void doWhenWindowReady(VoidCallback callback) {}

  @override
  DesktopWindow get appWindow {
    return AppWindowNotImplemented();
  }
}

class GtkWindow extends DesktopWindow {
  bool isButtonVisible(DesktopWindowButton button) => true;
  @override
  int? get handle => null;
  @override
  double get scaleFactor => 1.0;
  @override
  Rect get rect => Rect.zero;
  @override
  set rect(Rect newRect) {}
  @override
  Offset get position => Offset.zero;
  @override
  set position(Offset newPosition) {}
  @override
  Size get size => Size.zero;
  @override
  set size(Size newSize) {}
  @override
  set minSize(Size? newSize) {}
  @override
  set maxSize(Size? newSize) {}
  @override
  Size get screenSize => Size.zero;
  @override
  Size get workingScreenSize => Size.zero;

  @override
  Rect get workingScreenRect => Rect.zero;
  @override
  Alignment? get alignment => null;
  @override
  set alignment(Alignment? newAlignment) {}
  @override
  set title(String newTitle) {}
  @override
  bool get visible => false;
  @override
  bool get isVisible => false;
  @override
  set visible(bool isVisible) {}
  @override
  void show() {}
  @override
  void hide() {}
  @override
  void close() {}
  @override
  void minimize() {}
  @override
  void maximize() {}
  @override
  void maximizeOrRestore() {}
  void toggleFullScreen() {}
  @override
  void restore() {}
  @override
  void startDragging() {}
  @override
  bool get alwaysOnTop => false;
  @override
  set alwaysOnTop(bool onTop) {}
  @override
  bool get hasShadow => true;
  @override
  set hasShadow(bool value) {}
  @override
  Size get titleBarButtonSize => Size.zero;
  @override
  double get titleBarHeight => 0.0;
  @override
  set titleBarHeight(double height) {}
  @override
  double get borderSize => 0.0;
  @override
  bool get isMaximized => false;
  @override
  VoidCallback? get onClose => null;
  @override
  set onClose(VoidCallback? callback) {}
  @override
  VoidCallback? get onArgumentsChanged => null;
  @override
  set onArgumentsChanged(VoidCallback? callback) {}
  @override
  set backgroundEffect(WindowEffect effect) {}
  @override
  bool get isMainWindow => true;
  @override
  int get depth => 0;
  @override
  String? get name => null;
  @override
  Map<String, dynamic>? get arguments => null;
  @override
  Future<void> openNewWindow(
      {String? name,
      Size? size,
      Offset? position,
      Map<String, dynamic>? arguments}) async {}
}
