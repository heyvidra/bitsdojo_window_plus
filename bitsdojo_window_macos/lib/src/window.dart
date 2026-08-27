import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:flutter/widgets.dart';

import './native_api.dart';
import './window_util.dart';

bool isValidHandle(int? handle, String operation) {
  if (handle == null) {
    // Silently return false to avoid console clutter during startup race conditions
    return false;
  }
  return true;
}

class MacOSWindow extends DesktopWindow {
  static const DesktopWindowCapabilities _capabilities =
      DesktopWindowCapabilities(
        supportsBackgroundEffects: true,
        supportsTitleBarButtonVisibility: true,
        supportsTitleBarButtonOffset: true,
      );

  int? handle;
  Size? _minSize;
  Size? _maxSize;
  Alignment? _alignment;
  bool _setTitleOnNextShow = false;
  String? _titleToSet;

  MacOSWindow([this.handle]) {
    _alignment = Alignment.center;
    _setTitleOnNextShow = false;
  }

  @override
  DesktopWindowCapabilities get capabilities => _capabilities;

  Size get size {
    final winRect = this.rect;
    return Size(winRect.right - winRect.left, winRect.bottom - winRect.top);
  }

  Rect get rect {
    if (!isValidHandle(handle, "get rectangle")) return Rect.zero;
    return getRectForWindow(handle!);
  }

  double get scaleFactor {
    if (!isValidHandle(handle, "get scaleFactor")) return 1;
    return getWindowScaleFactor(handle!);
  }

  set rect(Rect newRect) {
    if (!isValidHandle(handle, "set rectangle")) return;
    // Clamp width to [minSize.width, maxSize.width]. Previously only
    // the minimum was enforced — keeping symmetry with `set size`
    // which clamps both bounds. Without the max-side clamp, a caller
    // that sets rect to a value > maxSize gets a window that
    // visually exceeds its declared max, which surprises downstream
    // layout code.
    var widthToSet = newRect.width;
    if (_minSize != null && widthToSet < _minSize!.width) {
      widthToSet = _minSize!.width;
    }
    if (_maxSize != null && widthToSet > _maxSize!.width) {
      widthToSet = _maxSize!.width;
    }
    var heightToSet = newRect.height;
    if (_minSize != null && heightToSet < _minSize!.height) {
      heightToSet = _minSize!.height;
    }
    if (_maxSize != null && heightToSet > _maxSize!.height) {
      heightToSet = _maxSize!.height;
    }
    final rectToSet =
        Rect.fromLTWH(newRect.left, newRect.top, widthToSet, heightToSet);
    setRectForWindow(handle!, rectToSet);
  }

  Offset get position {
    final winRect = this.rect;
    return Offset(winRect.left, winRect.top);
  }

  set position(Offset newPosition) {
    // An explicit position is an un-anchoring: a sticky alignment would
    // teleport the window back to the old anchor on the next resize.
    _alignment = null;
    _setPositionNative(newPosition);
  }

  void _setPositionNative(Offset newPosition) {
    if (!isValidHandle(handle, "set position")) return;
    setPositionForWindow(handle!, newPosition);
  }

  Alignment? get alignment => _alignment;
  set alignment(Alignment? newAlignment) {
    _alignment = newAlignment;
    if (_alignment != null) {
      if (!isValidHandle(handle, "set alignment")) return;
      final screenInfo = getScreenInfoForWindow(handle!);
      final windowRect =
          getRectOnScreen(this.size, _alignment!, screenInfo.workingRect);
      // workingRect and the position setter share one space now (distance
      // from the full screen top), so the topLeft feeds through unchanged.
      // The old -menuBarHeight fudge compensated for setters and getters
      // living in different spaces; with the native getter unified it would
      // lift every aligned window a menu bar height too high.
      // Raw native call: the public position setter would clear the anchor
      // we just set.
      _setPositionNative(windowRect.topLeft);
    }
  }

  set minSize(Size? newSize) {
    if (!isValidHandle(handle, "set minSize")) return;
    if (newSize != null && _maxSize != null) {
      assert(newSize.width <= _maxSize!.width && newSize.height <= _maxSize!.height,
          'minSize ($newSize) must not exceed maxSize ($_maxSize)');
    }
    _minSize = newSize;
    setMinSize(
        handle!, newSize?.width.toInt() ?? 0, newSize?.height.toInt() ?? 0);
  }

  set maxSize(Size? newSize) {
    if (!isValidHandle(handle, "set maxSize")) return;
    if (newSize != null && _minSize != null) {
      assert(newSize.width >= _minSize!.width && newSize.height >= _minSize!.height,
          'maxSize ($newSize) must not be less than minSize ($_minSize)');
    }
    _maxSize = newSize;
    setMaxSize(
        handle!, newSize?.width.toInt() ?? -1, newSize?.height.toInt() ?? -1);
  }

  @override
  Size get screenSize {
    if (!isValidHandle(handle, "get screenSize")) return Size.zero;
    final screenInfo = getScreenInfoForWindow(handle!);
    return screenInfo.fullRect.size;
  }

  @override
  Size get workingScreenSize {
    if (!isValidHandle(handle, "get workingScreenSize")) return Size.zero;
    final screenInfo = getScreenInfoForWindow(handle!);
    return screenInfo.workingRect.size;
  }

  @override
  Rect get workingScreenRect {
    if (!isValidHandle(handle, "get workingScreenRect")) return Rect.zero;
    final screenInfo = getScreenInfoForWindow(handle!);
    return screenInfo.workingRect;
  }

  set size(Size newSize) {
    if (!isValidHandle(handle, "set size")) return;
    var width = newSize.width;

    if (_minSize != null) {
      if (newSize.width < _minSize!.width) width = _minSize!.width;
    }

    if (_maxSize != null) {
      if (newSize.width > _maxSize!.width) width = _maxSize!.width;
    }

    var height = newSize.height;

    if (_minSize != null) {
      if (newSize.height < _minSize!.height) height = _minSize!.height;
    }

    if (_maxSize != null) {
      if (newSize.height > _maxSize!.height) height = _maxSize!.height;
    }

    Size sizeToSet = Size(width, height);
    if (_alignment == null) {
      setSize(handle!, sizeToSet.width.toInt(), sizeToSet.height.toInt());
    } else {
      final screenInfo = getScreenInfoForWindow(handle!);
      this.rect = getRectOnScreen(sizeToSet, _alignment!, screenInfo.workingRect);
    }
  }

  Size get titleBarButtonSize {
    if (!isValidHandle(handle, "get titleBarButtonSize")) return Size.zero;
    return getTitleBarButtonSize(handle!);
  }

  double get titleBarHeight {
    if (!isValidHandle(handle, "get titleBarHeight")) return 0;
    return getTitleBarHeight(handle!);
  }

  @override
  set titleBarHeight(double height) {
    if (!isValidHandle(handle, "set titleBarHeight")) return;
    setTitleBarHeight(handle!, height.toInt());
  }

  set title(String newTitle) {
    if (!isValidHandle(handle, "set title")) return;
    // Save title internally because window might be hidden
    // so title won't be set. Will set it on next show()
    if (this.isVisible == false) {
      _setTitleOnNextShow = true;
      _titleToSet = newTitle;
    }
    setWindowTitle(handle!, newTitle);
  }

  double get borderSize {
    //borderSize is zero on macOS
    return 0;
  }

  bool get isVisible {
    if (!isValidHandle(handle, "get isVisible")) return false;
    return isWindowVisible(handle!);
  }

  void show() {
    if (!isValidHandle(handle, "show")) return;
    showWindow(handle!);
    if (_setTitleOnNextShow) {
      _setTitleOnNextShow = false;
      if (_titleToSet != null) {
        setWindowTitle(handle!, _titleToSet!);
      }
    }
  }

  void hide() {
    if (!isValidHandle(handle, "hide")) return;
    hideWindow(handle!);
  }

  void close() {
    if (!isValidHandle(handle, "close")) return;
    closeWindow(handle!);
  }

  void minimize() {
    if (!isValidHandle(handle, "minimize")) return;
    minimizeWindow(handle!);
  }

  void maximize() {
    if (!isValidHandle(handle, "maximize")) return;
    maximizeWindow(handle!);
  }

  void restore() {
    if (this.isMaximized) {
      maximizeOrRestore();
    }
  }

  bool get isMaximized {
    if (!isValidHandle(handle, "get isMaximized")) return false;
    return isWindowMaximized(handle!);
  }

  void startDragging() {
    if (!isValidHandle(handle, "start dragging")) return;
    moveWindow(handle!);
  }

  void maximizeOrRestore() {
    if (!isValidHandle(handle, "maximizeOrRestore")) return;
    maximizeOrRestoreWindow(handle!);
  }

  @override
  void toggleFullScreen() {
    if (!isValidHandle(handle, "toggleFullScreen")) return;
    toggleFullScreenWindow(handle!);
  }

  bool get alwaysOnTop {
    if (!isValidHandle(handle, "get alwaysOnTop")) return false;
    return isAlwaysOnTop(handle!);
  }

  set alwaysOnTop(bool onTop) {
    if (!isValidHandle(handle, "set alwaysOnTop")) return;
    todoAlwaysOnTop(handle!, onTop ? 1 : 0);
  }

  VoidCallback? _onClose;
  @override
  set onClose(VoidCallback? callback) {
    _onClose = callback;
  }

  @override
  VoidCallback? get onClose => _onClose;

  VoidCallback? _onArgumentsChanged;
  @override
  set onArgumentsChanged(VoidCallback? callback) {
    _onArgumentsChanged = callback;
  }

  @override
  VoidCallback? get onArgumentsChanged => _onArgumentsChanged;

  @override
  set backgroundEffect(WindowEffect effect) {
    if (!isValidHandle(handle, "set backgroundEffect")) return;
    setBackgroundEffect(handle!, effect.index);
  }

  @override
  bool get isMainWindow =>
      BitsdojoWindowPlatform.instance.isMainWindow(this.handle ?? 0);

  int _depth = 0;
  String? _name;
  Map<String, dynamic>? _arguments;

  @override
  int get depth => _depth;
  set depth(int value) => _depth = value;

  @override
  String? get name => _name;
  set name(String? value) => _name = value;

  @override
  Map<String, dynamic>? get arguments => _arguments;
  set arguments(Map<String, dynamic>? value) => _arguments = value;

  @override
  void setWindowTitleBarButtonVisibility(
      DesktopWindowButton button, bool visible) {
    if (!isValidHandle(handle, "set window button visibility")) return;
    setWindowButtonVisibility(handle!, button.index, visible);
  }

  @override
  void setWindowTitleBarButtonOffset(
      DesktopWindowButton button, Offset offset) {
    if (!isValidHandle(handle, "set window button offset")) return;
    setWindowButtonOffset(handle!, button.index, offset.dx, offset.dy);
  }

  @override
  bool get hasShadow {
    if (!isValidHandle(handle, "get hasShadow")) return true;
    return isHasShadowNative(handle!) == 1;
  }

  @override
  set hasShadow(bool value) {
    if (!isValidHandle(handle, "set hasShadow")) return;
    setHasShadowNative(handle!, value ? 1 : 0);
  }
}
