import 'dart:ffi' hide Size;

import 'dart:io';
import 'dart:convert';
import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import './gtk.dart';
import './native_api.dart' as native;

var isInsideDoWhenWindowReady = false;

bool isValidHandle(int? handle, String operation) {
  if (handle == null) {
    debugPrint("bitsdojo_window: could not $operation - handle is null");
    return false;
  }
  return true;
}

class CachedWindowInfo {
  Rect? rect;
}

Rect getScreenRectForWindow(int handle) {
  Pointer<Int32> gtkRect = malloc.allocate(sizeOf<Int32>() * 4);
  native.getScreenRect(handle, gtkRect, gtkRect + 1, gtkRect + 2, gtkRect + 3);
  Rect result = Rect.fromLTWH(gtkRect[0].toDouble(), gtkRect[1].toDouble(),
      gtkRect[2].toDouble(), gtkRect[3].toDouble());
  malloc.free(gtkRect);

  return result;
}

class GtkWindow extends DesktopWindow {
  static const DesktopWindowCapabilities _capabilities =
      DesktopWindowCapabilities(
        supportsTitleBarButtonVisibility: true,
      );

  int? handle;
  Size? _minSize;
  Size? _maxSize;
  Alignment? _alignment;
  double _titleBarHeight = 32.0;
  // size and position are cached during doWhenWindowReady
  // because the window operations for setting size/position
  // are scheduled and do not run immediately so the results
  // from native getSize/getPosition are not reliable
  // immediatly after the operation

  CachedWindowInfo _cached = CachedWindowInfo();

  GtkWindow([int? handle]) {
    this.handle = handle;
  }

  @override
  DesktopWindowCapabilities get capabilities => _capabilities;

  @override
  bool get isVisible {
    if (!isValidHandle(handle, "get isVisible")) return false;
    return gtkWidgetGetVisible(handle!) != 0;
  }

  @override
  Rect get rect {
    if (!isValidHandle(handle, "get rectangle")) return Rect.zero;

    if (isInsideDoWhenWindowReady == true && _cached.rect != null) {
      return _cached.rect!;
    }

    Pointer<Int32> gtkRect = malloc.allocate(sizeOf<Int32>() * 4);
    native.getPosition(handle!, gtkRect, gtkRect + 1);
    native.getSize(handle!, gtkRect + 2, gtkRect + 3);
    Rect result = Rect.fromLTWH(gtkRect[0].toDouble(), gtkRect[1].toDouble(),
        gtkRect[2].toDouble(), gtkRect[3].toDouble());

    malloc.free(gtkRect);
    return result;
  }

  @override
  set rect(Rect newRect) {
    if (!isValidHandle(handle, "set rectangle")) return;
    _cached.rect = newRect;
    native.setRect(handle!, newRect.left.toInt(), newRect.top.toInt(),
        newRect.width.toInt(), newRect.height.toInt());
  }

  @override
  Size get size {
    if (!isValidHandle(handle, "get size")) return Size.zero;

    if (isInsideDoWhenWindowReady == true && _cached.rect != null) {
      return _cached.rect!.size;
    }

    Pointer<Int32> nativeResult = malloc.allocate(sizeOf<Int32>() * 2);
    native.getSize(handle!, nativeResult, nativeResult + 1);
    Size result = Size(nativeResult[0].toDouble(), nativeResult[1].toDouble());
    malloc.free(nativeResult);
    final gotSize = getLogicalSize(result);
    return gotSize;
  }

  Size get sizeOnScreen {
    if (isInsideDoWhenWindowReady == true && _cached.rect != null) {
      final sizeOnScreen = getSizeOnScreen(_cached.rect!.size);
      return sizeOnScreen;
    }
    final winRect = this.rect;
    return Size(winRect.width, winRect.height);
  }

  @override
  double get borderSize {
    return 0.0;
  }

  int get dpi {
    return (96.0 * this.scaleFactor).toInt();
  }

  @override
  double get scaleFactor {
    if (!isValidHandle(handle, "get scaleFactor")) return 1;
    Pointer<Int32> scaleFactorPtr = malloc.allocate(sizeOf<Int32>());
    native.getScaleFactor(handle!, scaleFactorPtr);
    final rawValue = scaleFactorPtr[0];
    malloc.free(scaleFactorPtr);
    if (rawValue <= 0) {
      return 1;
    }
    return rawValue.toDouble();
  }

  @override
  double get titleBarHeight {
    return _titleBarHeight;
  }

  @override
  set titleBarHeight(double height) {
    _titleBarHeight = height;
  }

  @override
  Size get titleBarButtonSize {
    Size result = Size(32, _titleBarHeight);
    return result;
  }

  Size getSizeOnScreen(Size inSize) {
    final scaleFactor = this.scaleFactor;
    double newWidth = inSize.width * scaleFactor;
    double newHeight = inSize.height * scaleFactor;
    return Size(newWidth, newHeight);
  }

  Size getLogicalSize(Size inSize) {
    final scaleFactor = this.scaleFactor;
    if (scaleFactor <= 0) {
      return inSize;
    }
    double newWidth = inSize.width / scaleFactor;
    double newHeight = inSize.height / scaleFactor;
    return Size(newWidth, newHeight);
  }

  @override
  Alignment? get alignment => _alignment;

  /// How the window should be aligned on screen
  @override
  set alignment(Alignment? newAlignment) {
    final sizeOnScreen = this.sizeOnScreen;
    _alignment = newAlignment;
    if (_alignment != null) {
      if (!isValidHandle(handle, "set alignment")) return;
      final screenRect = getScreenRectForWindow(handle!);
      this.rect = getRectOnScreen(sizeOnScreen, _alignment!, screenRect);
    }
  }

  @override
  set minSize(Size? newSize) {
    if (!isValidHandle(handle, "set minSize")) return;
    if (newSize != null && _maxSize != null) {
      assert(newSize.width <= _maxSize!.width && newSize.height <= _maxSize!.height,
          'minSize ($newSize) must not exceed maxSize ($_maxSize)');
    }
    _minSize = newSize;
    native.setMinSize(
        handle!, newSize?.width.toInt() ?? -1, newSize?.height.toInt() ?? -1);
  }

  @override
  set maxSize(Size? newSize) {
    if (!isValidHandle(handle, "set maxSize")) return;
    if (newSize != null && _minSize != null) {
      assert(newSize.width >= _minSize!.width && newSize.height >= _minSize!.height,
          'maxSize ($newSize) must not be less than minSize ($_minSize)');
    }
    _maxSize = newSize;
    native.setMaxSize(
        handle!, newSize?.width.toInt() ?? -1, newSize?.height.toInt() ?? -1);
  }

  @override
  Size get screenSize {
    if (!isValidHandle(handle, "get screenSize")) return Size.zero;
    final rect = getScreenRectForWindow(handle!);
    return getLogicalSize(rect.size);
  }

  @override
  Size get workingScreenSize {
    return screenSize; // GTK getScreenRect returns monitor geometry
  }

  @override
  Rect get workingScreenRect {
    if (!isValidHandle(handle, "get workingScreenRect")) return Rect.zero;
    final rect = getScreenRectForWindow(handle!);
    return Rect.fromLTWH(
      rect.left / scaleFactor,
      rect.top / scaleFactor,
      rect.width / scaleFactor,
      rect.height / scaleFactor,
    );
  }

  @override
  set size(Size newSize) {
    if (!isValidHandle(handle, "set size")) return;
    if (!newSize.width.isFinite || !newSize.height.isFinite) return;

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

    // Save cached rect
    final double left = _cached.rect != null ? _cached.rect!.left : 0;
    final double top = _cached.rect != null ? _cached.rect!.top : 0;
    _cached.rect = Rect.fromLTWH(left, top, width, height);

    if (_alignment == null) {
      native.setSize(
          handle!, sizeToSet.width.toInt(), sizeToSet.height.toInt());
      //native.setWindowSize(handle!, sizeToSet);
    } else {
      final sizeOnScreen = getSizeOnScreen((sizeToSet));
      final screenRect = getScreenRectForWindow(handle!);
      this.rect = getRectOnScreen(sizeOnScreen, _alignment!, screenRect);
    }
  }

  @override
  bool get isMaximized {
    if (!isValidHandle(handle, "get isMaximized")) return false;
    return gtkWindowIsMaximized(handle!) == 1;
  }

  @override
  Offset get position {
    if (isInsideDoWhenWindowReady == true && _cached.rect != null) {
      return _cached.rect!.topLeft;
    }
    return this.rect.topLeft;
  }

  @override
  set position(Offset newPosition) {
    if (!isValidHandle(handle, "set position")) return;
    if (!newPosition.dx.isFinite || !newPosition.dy.isFinite) return;
    // An explicit position is an un-anchoring: a sticky alignment would
    // teleport the window back to the old anchor on the next resize.
    _alignment = null;
    // Save cached rect
    final double width = _cached.rect != null ? _cached.rect!.width : 0;
    final double height = _cached.rect != null ? _cached.rect!.height : 0;
    _cached.rect = Rect.fromLTWH(newPosition.dx, newPosition.dy, width, height);
    native.setPosition(handle!, newPosition.dx.toInt(), newPosition.dy.toInt());
  }

  @override
  void show() {
    if (!isValidHandle(handle, "show")) return;
    Offset currentPosition = this.position;
    native.showWindow(handle!);
    this.position = currentPosition;
  }

  @override
  void hide() {
    if (!isValidHandle(handle, "hide")) return;
    native.hideWindow(handle!);
  }

  @Deprecated("use show()/hide() instead")

  @override
  void close() {
    if (!isValidHandle(handle, "close")) return;
    gtkWindowClose(handle!);
  }

  @override
  void maximize() {
    if (!isValidHandle(handle, "maximize")) return;
    native.maximizeWindow(handle!);
  }

  @override
  void minimize() {
    if (!isValidHandle(handle, "minimize")) return;
    native.minimizeWindow(handle!);
  }

  @override
  void restore() {
    if (!isValidHandle(handle, "restore")) return;
    native.unmaximizeWindow(handle!);
  }

  @override
  void maximizeOrRestore() {
    if (!isValidHandle(handle, "maximizeOrRestore")) return;
    if (this.isMaximized) {
      this.restore();
    } else {
      this.maximize();
    }
  }

  @override
  void toggleFullScreen() {
    if (!isValidHandle(handle, "toggleFullScreen")) return;
    native.toggleFullScreenWindow(handle!);
  }

  @override
  set title(String newTitle) {
    if (!isValidHandle(handle, "set title")) return;
    final nativeString = newTitle.toNativeUtf8();
    try {
      native.setWindowTitle(handle!, nativeString);
    } finally {
      malloc.free(nativeString);
    }
  }

  final Map<DesktopWindowButton, bool> _buttonVisibility = {};

  bool isButtonVisible(DesktopWindowButton button) {
    return _buttonVisibility[button] ?? true;
  }

  @override
  void startDragging() {
    BitsdojoWindowPlatform.instance.dragAppWindow();
  }

  bool _alwaysOnTop = false;
  @override
  bool get alwaysOnTop {
    return _alwaysOnTop;
  }

  @override
  set alwaysOnTop(bool onTop) {
    _alwaysOnTop = onTop;
    BitsdojoWindowPlatform.instance.setAlwaysOnTop(onTop);
  }

  @override
  bool get hasShadow => true;

  @override
  set hasShadow(bool value) {}

  VoidCallback? _onClose;
  @override
  set onClose(VoidCallback? callback) {
    _onClose = callback;
  }

  @override
  VoidCallback? get onClose => _onClose;

  @override
  VoidCallback? onArgumentsChanged;

  @override
  set backgroundEffect(WindowEffect effect) {
    BitsdojoWindowPlatform.instance.setBackgroundEffect(effect);
  }

  @override
  void setWindowTitleBarButtonVisibility(
      DesktopWindowButton button, bool visible) {
    _buttonVisibility[button] = visible;
    BitsdojoWindowPlatform.instance
        .setWindowTitleBarButtonVisibility(button, visible);
  }

  @override
  bool get isMainWindow => depth == 0;

  @override
  int get depth => int.tryParse(Platform.environment['BDW_DEPTH'] ?? '') ?? 0;

  @override
  String? get name {
    final envName = Platform.environment['BDW_NAME'];
    if (envName == null || envName.isEmpty) return null;
    return envName;
  }

  Map<String, dynamic>? _arguments;

  @override
  Map<String, dynamic>? get arguments {
    if (_arguments != null) return _arguments;
    final envArgs = Platform.environment['BDW_ARGS'];
    if (envArgs == null || envArgs.isEmpty) return null;
    try {
      return jsonDecode(envArgs) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  set arguments(Map<String, dynamic>? value) {
    _arguments = value;
  }
}
