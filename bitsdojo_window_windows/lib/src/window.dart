import 'dart:ffi' hide Size;

import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:win32/win32.dart';

import './native_api.dart' as native;
import './win32_plus.dart';
import './window_interface.dart';
import './window_util.dart';

var isInsideDoWhenWindowReady = false;

bool isValidHandle(HWND? handle, String operation) {
  if (handle == null) {
    debugPrint("bitsdojo_window: could not $operation - handle is null");
    return false;
  }
  return true;
}

Rect getScreenRectForWindow(HWND handle) {
  final monitor = MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST);
  final monitorInfo = calloc<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
  final result = GetMonitorInfo(monitor, monitorInfo);
  if (result) {
    return Rect.fromLTRB(
        monitorInfo.ref.rcWork.left.toDouble(),
        monitorInfo.ref.rcWork.top.toDouble(),
        monitorInfo.ref.rcWork.right.toDouble(),
        monitorInfo.ref.rcWork.bottom.toDouble());
  }
  return Rect.zero;
}

Rect getScreenFullRectForWindow(HWND handle) {
  final monitor = MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST);
  final monitorInfo = calloc<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
  final result = GetMonitorInfo(monitor, monitorInfo);
  if (result) {
    return Rect.fromLTRB(
        monitorInfo.ref.rcMonitor.left.toDouble(),
        monitorInfo.ref.rcMonitor.top.toDouble(),
        monitorInfo.ref.rcMonitor.right.toDouble(),
        monitorInfo.ref.rcMonitor.bottom.toDouble());
  }
  return Rect.zero;
}

class WinWindow extends WinDesktopWindow {
  static const DesktopWindowCapabilities _capabilities =
      DesktopWindowCapabilities(
    supportsBackgroundEffects: true,
  );

  static final dpiAware = native.isDPIAware();
  // handle is stored as int (from MethodChannel) and wrapped to HWND on use
  int? _handleInt;
  Size? _minSize;
  Size? _maxSize;
  double? _customTitleBarHeight;
  // We use this for reporting size inside doWhenWindowReady
  // as GetWindowRect might not work reliably before window is shown on screen
  Size? _sizeSetFromDart;
  Alignment? _alignment;
  bool _isFullScreen = false;
  int _savedStyle = 0;
  int _savedExStyle = 0;
  Pointer<WINDOWPLACEMENT>? _savedPlacement;

  WinWindow([int? handle]) {
    _handleInt = handle;
    _alignment = Alignment.center;
  }

  /// Raw int handle (as received from MethodChannel / native API).
  int? get handle => _handleInt;
  set handle(int? value) => _handleInt = value;

  /// win32 v6 HWND extension type, or null when not yet available.
  HWND? get _hwnd => _handleInt != null ? HWND(Pointer.fromAddress(_handleInt!)) : null;

  @override
  DesktopWindowCapabilities get capabilities => _capabilities;

  Rect get rect {
    if (!isValidHandle(_hwnd, "get rectangle")) return Rect.zero;
    final winRect = calloc<RECT>();
    GetWindowRect(_hwnd!, winRect);
    Rect result = winRect.ref.toRect;
    calloc.free(winRect);
    return result;
  }

  set rect(Rect newRect) {
    if (!isValidHandle(_hwnd, "set rectangle")) return;
    setWindowPos(_hwnd!, HWND(Pointer.fromAddress(0)), newRect.left.toInt(), newRect.top.toInt(),
        newRect.width.toInt(), newRect.height.toInt(), 0);
  }

  Size get size {
    final winRect = this.rect;
    final gotSize = getLogicalSize(Size(winRect.width, winRect.height));
    return gotSize;
  }

  Size get sizeOnScreen {
    if (isInsideDoWhenWindowReady == true) {
      if (_sizeSetFromDart != null) {
        final sizeOnScreen = getSizeOnScreen(_sizeSetFromDart!);
        return sizeOnScreen;
      }
    }
    final winRect = this.rect;
    return Size(winRect.width, winRect.height);
  }

  double systemMetric(SYSTEM_METRICS_INDEX metric, {int dpiToUse = 0}) {
    final windowDpi = dpiToUse != 0 ? dpiToUse : this.dpi;
    double result = dpiAware
        ? GetSystemMetricsForDpi(metric, windowDpi).value.toDouble()
        : GetSystemMetrics(metric).toDouble();
    return result;
  }

  double get borderSize {
    return this.systemMetric(SM_CXBORDER);
  }

  int get dpi {
    if (!dpiAware || !isValidHandle(_hwnd, "get dpi")) return 96;
    return GetDpiForWindow(_hwnd!);
  }

  double get scaleFactor {
    double result = this.dpi / 96.0;
    return result;
  }

  double get titleBarHeight {
    if (_customTitleBarHeight != null) {
      return _customTitleBarHeight!;
    }
    double scaleFactor = this.scaleFactor;
    int dpiToUse = this.dpi;
    double cyCaption = systemMetric(SM_CYCAPTION, dpiToUse: dpiToUse);
    cyCaption = (cyCaption / scaleFactor);
    double cySizeFrame = systemMetric(SM_CYSIZEFRAME, dpiToUse: dpiToUse);
    cySizeFrame = (cySizeFrame / scaleFactor);
    double cxPaddedBorder =
        systemMetric(SM_CXPADDEDBORDER, dpiToUse: dpiToUse);
    cxPaddedBorder = (cxPaddedBorder / scaleFactor).ceilToDouble();
    double result = cySizeFrame + cyCaption + cxPaddedBorder;
    return result;
  }

  @override
  set titleBarHeight(double height) {
    _customTitleBarHeight = height;
  }

  void setWindowCutOnMaximize(int value) {
    if (!isValidHandle(_hwnd, "set window cut on maximize")) return;
    native.setWindowCutOnMaximize(_handleInt!, value);
  }

  Size get titleBarButtonSize {
    double height = this.titleBarHeight - this.borderSize;
    double scaleFactor = this.scaleFactor;
    double cyCaption = systemMetric(SM_CYCAPTION);
    cyCaption /= scaleFactor;
    double width = cyCaption * 2;
    return Size(width, height);
  }

  Size getSizeOnScreen(Size inSize) {
    double scaleFactor = this.scaleFactor;
    double newWidth = inSize.width * scaleFactor;
    double newHeight = inSize.height * scaleFactor;
    return Size(newWidth, newHeight);
  }

  Size getLogicalSize(Size inSize) {
    double scaleFactor = this.scaleFactor;
    double newWidth = inSize.width / scaleFactor;
    double newHeight = inSize.height / scaleFactor;
    return Size(newWidth, newHeight);
  }

  Alignment? get alignment => _alignment;

  /// How the window should be aligned on screen
  set alignment(Alignment? newAlignment) {
    final sizeOnScreen = this.sizeOnScreen;
    _alignment = newAlignment;
    if (_alignment != null) {
      if (!isValidHandle(_hwnd, "set alignment")) return;
      final screenRect = getScreenRectForWindow(_hwnd!);
      final rectOnScreen =
          getRectOnScreen(sizeOnScreen, _alignment!, screenRect);
      this.rect = rectOnScreen;
    }
  }

  set minSize(Size? newSize) {
    if (newSize != null && _maxSize != null) {
      assert(
          newSize.width <= _maxSize!.width &&
              newSize.height <= _maxSize!.height,
          'minSize ($newSize) must not exceed maxSize ($_maxSize)');
    }
    _minSize = newSize;
    if (!isValidHandle(_hwnd, "set min size")) return;
    native.setMinSize(
        _handleInt!, newSize?.width.toInt() ?? 0, newSize?.height.toInt() ?? 0);
  }

  set maxSize(Size? newSize) {
    if (newSize != null && _minSize != null) {
      assert(
          newSize.width >= _minSize!.width &&
              newSize.height >= _minSize!.height,
          'maxSize ($newSize) must not be less than minSize ($_minSize)');
    }
    _maxSize = newSize;
    if (!isValidHandle(_hwnd, "set max size")) return;
    native.setMaxSize(
        _handleInt!, newSize?.width.toInt() ?? 0, newSize?.height.toInt() ?? 0);
  }

  @override
  Size get screenSize {
    if (!isValidHandle(_hwnd, "get screenSize")) return Size.zero;
    final rect = getScreenFullRectForWindow(_hwnd!);
    return getLogicalSize(rect.size);
  }

  @override
  Size get workingScreenSize {
    if (!isValidHandle(_hwnd, "get workingScreenSize")) return Size.zero;
    final rect = getScreenRectForWindow(_hwnd!);
    return getLogicalSize(rect.size);
  }

  @override
  Rect get workingScreenRect {
    if (!isValidHandle(_hwnd, "get workingScreenRect")) return Rect.zero;
    final rect = getScreenRectForWindow(_hwnd!);
    return Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width / scaleFactor,
      rect.height / scaleFactor,
    );
  }

  set size(Size newSize) {
    if (!isValidHandle(_hwnd, "set size")) return;

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
    _sizeSetFromDart = sizeToSet;
    if (_alignment == null) {
      SetWindowPos(_hwnd!, HWND(Pointer.fromAddress(0)), 0, 0, sizeToSet.width.toInt(),
          sizeToSet.height.toInt(), SWP_NOMOVE);
    } else {
      final sizeOnScreen = getSizeOnScreen((sizeToSet));
      final screenRect = getScreenRectForWindow(_hwnd!);
      this.rect = getRectOnScreen(sizeOnScreen, _alignment!, screenRect);
    }
  }

  bool get isMaximized {
    if (!isValidHandle(_hwnd, "get isMaximized")) return false;
    return IsZoomed(_hwnd!);
  }

  @Deprecated("use isVisible instead")
  bool get visible {
    return isVisible;
  }

  bool get isVisible {
    if (!isValidHandle(_hwnd, "get isVisible")) return false;
    return IsWindowVisible(_hwnd!);
  }

  Offset get position {
    final winRect = this.rect;
    return Offset(winRect.left, winRect.top);
  }

  set position(Offset newPosition) {
    if (!isValidHandle(_hwnd, "set position")) return;
    // An explicit position is an un-anchoring: a sticky alignment would
    // teleport the window back to the old anchor on the next resize.
    _alignment = null;
    SetWindowPos(_hwnd!, HWND(Pointer.fromAddress(0)), newPosition.dx.toInt(),
        newPosition.dy.toInt(), 0, 0, SWP_NOSIZE);
  }

  void show() {
    if (!isValidHandle(_hwnd, "show")) return;
    setWindowPos(
        _hwnd!, HWND(Pointer.fromAddress(0)), 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW);
    forceChildRefresh(_hwnd!);
  }

  void hide() {
    if (!isValidHandle(_hwnd, "hide")) return;
    SetWindowPos(
        _hwnd!, HWND(Pointer.fromAddress(0)), 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_HIDEWINDOW);
  }

  @Deprecated("use show()/hide() instead")
  set visible(bool isVisible) {
    if (isVisible) {
      show();
    } else {
      hide();
    }
  }

  void close() {
    if (!isValidHandle(_hwnd, "close")) return;
    native.setCloseRequestedCallback(_handleInt!, nullptr);
    PostMessage(_hwnd!, WM_SYSCOMMAND, WPARAM(SC_CLOSE), LPARAM(0));
  }

  void maximize() {
    if (!isValidHandle(_hwnd, "maximize")) return;
    PostMessage(_hwnd!, WM_SYSCOMMAND, WPARAM(SC_MAXIMIZE), LPARAM(0));
  }

  void minimize() {
    if (!isValidHandle(_hwnd, "minimize")) return;
    PostMessage(_hwnd!, WM_SYSCOMMAND, WPARAM(SC_MINIMIZE), LPARAM(0));
  }

  void restore() {
    if (!isValidHandle(_hwnd, "restore")) return;
    PostMessage(_hwnd!, WM_SYSCOMMAND, WPARAM(SC_RESTORE), LPARAM(0));
  }

  void maximizeOrRestore() {
    if (!isValidHandle(_hwnd, "maximizeOrRestore")) return;
    if (IsZoomed(_hwnd!)) {
      this.restore();
    } else {
      this.maximize();
    }
  }

  void toggleFullScreen() {
    if (!isValidHandle(_hwnd, "toggleFullScreen")) return;

    if (!_isFullScreen) {
      _savedStyle = GetWindowLongPtr(_hwnd!, GWL_STYLE).value;
      _savedExStyle = GetWindowLongPtr(_hwnd!, GWL_EXSTYLE).value;
      _savedPlacement ??= calloc<WINDOWPLACEMENT>();
      _savedPlacement!.ref.length = sizeOf<WINDOWPLACEMENT>();
      GetWindowPlacement(_hwnd!, _savedPlacement!);

      final monitor = MonitorFromWindow(_hwnd!, MONITOR_DEFAULTTONEAREST);
      final monitorInfo = calloc<MONITORINFO>()
        ..ref.cbSize = sizeOf<MONITORINFO>();
      GetMonitorInfo(monitor, monitorInfo);

      final screenRect = monitorInfo.ref.rcMonitor;

      SetWindowLongPtr(
          _hwnd!, GWL_STYLE, _savedStyle & ~(WS_CAPTION | WS_THICKFRAME));
      SetWindowLongPtr(
          _hwnd!,
          GWL_EXSTYLE,
          _savedExStyle &
              ~(WS_EX_DLGMODALFRAME |
                  WS_EX_WINDOWEDGE |
                  WS_EX_CLIENTEDGE |
                  WS_EX_STATICEDGE));

      SetWindowPos(
          _hwnd!,
          HWND_TOP,
          screenRect.left,
          screenRect.top,
          screenRect.right - screenRect.left,
          screenRect.bottom - screenRect.top,
          SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);

      calloc.free(monitorInfo);
      _isFullScreen = true;
    } else {
      SetWindowLongPtr(_hwnd!, GWL_STYLE, _savedStyle);
      SetWindowLongPtr(_hwnd!, GWL_EXSTYLE, _savedExStyle);

      if (_savedPlacement != null) {
        SetWindowPlacement(_hwnd!, _savedPlacement!);
        calloc.free(_savedPlacement!);
        _savedPlacement = null;
      }

      SetWindowPos(
          _hwnd!,
          HWND(Pointer.fromAddress(0)),
          0,
          0,
          0,
          0,
          SWP_NOMOVE |
              SWP_NOSIZE |
              SWP_NOZORDER |
              SWP_NOACTIVATE |
              SWP_FRAMECHANGED);
      _isFullScreen = false;
    }
  }

  set title(String newTitle) {
    if (!isValidHandle(_hwnd, "set title")) return;
    setWindowText(_hwnd!, newTitle);
  }

  void startDragging() {
    BitsdojoWindowPlatform.instance.dragAppWindow();
  }

  bool get alwaysOnTop {
    if (!isValidHandle(_hwnd, "get alwaysOnTop")) return false;
    return native.isAlwaysOnTop(_handleInt!);
  }

  set alwaysOnTop(bool onTop) {
    if (!isValidHandle(_hwnd, "set alwaysOnTop")) return;
    native.setAlwaysOnTop(_handleInt!, onTop ? 1 : 0);
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
    if (!isValidHandle(_hwnd, "set backgroundEffect")) return;
    native.setBackgroundEffect(_handleInt!, effect.index);
  }

  bool _isMainWindow = true;
  @override
  bool get isMainWindow => _isMainWindow;
  set isMainWindow(bool value) => _isMainWindow = value;

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
  Future<void> openNewWindow({
    String? name,
    Size? size,
    Offset? position,
    Map<String, dynamic>? arguments,
  }) {
    return BitsdojoWindowPlatform.instance.openNewWindow(
      name: name,
      size: size,
      position: position,
      arguments: arguments,
    );
  }
}
