library bitsdojo_window_macos;

import 'dart:ffi' hide Size;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';

import './native_struct.dart';

final DynamicLibrary _appExecutable = DynamicLibrary.executable();

const BDW_SUCCESS = 1;

// Native function types

// First line - native function type definition
// Second line - dart function type definition
// Third line - dart function type instance

// getAppWindow
typedef IntPtr TGetAppWindow();
typedef DGetAppWindow = int Function();
final DGetAppWindow getAppWindow = _publicAPI.ref.getAppWindow.asFunction();

// setWindowCanBeShown
typedef Void TSetWindowCanBeShown(IntPtr window, Int8 value);
typedef DSetWindowCanBeShown = void Function(int window, int value);
final DSetWindowCanBeShown _setWindowCanBeShown =
    _publicAPI.ref.setWindowCanBeShown.asFunction();
void setWindowCanBeShown(int window, bool value) =>
    _setWindowCanBeShown(window, value ? 1 : 0);

// setInsideDoWhenWindowReady
typedef Void TSetInsideDoWhenWindowReady(Int8 value);
typedef DSetInsideDoWhenWindowReady = void Function(int value);
final DSetInsideDoWhenWindowReady _setInsideDoWhenWindowReady =
    _publicAPI.ref.setInsideDoWhenWindowReady.asFunction();
void setInsideDoWhenWindowReady(bool value) =>
    _setInsideDoWhenWindowReady(value ? 1 : 0);

// showWindow
typedef Void TShowWindow(IntPtr window);
typedef DShowWindow = void Function(int window);
final DShowWindow showWindow = _publicAPI.ref.showWindow.asFunction();

// hideWindow
typedef Void THideWindow(IntPtr window);
typedef DHideWindow = void Function(int window);
final DHideWindow hideWindow = _publicAPI.ref.hideWindow.asFunction();

// moveWindow
typedef Void TMoveWindow(IntPtr window);
typedef DMoveWindow = void Function(int window);
final DMoveWindow moveWindow = _publicAPI.ref.moveWindow.asFunction();

// setSize
typedef Void TSetSize(IntPtr window, Int32 first, Int32 second);
typedef DSetSize = void Function(int window, int first, int second);
final DSetSize setSize = _publicAPI.ref.setSize.asFunction();

// setMinSize
typedef Void TSetMinSize(IntPtr window, Int32 first, Int32 second);
typedef DSetMinSize = void Function(int window, int first, int second);
final DSetMinSize setMinSize = _publicAPI.ref.setMinSize.asFunction();

// setMaxSize
typedef Void TSetMaxSize(IntPtr window, Int32 first, Int32 second);
typedef DSetMaxSize = void Function(int window, int first, int second);
final DSetMaxSize setMaxSize = _publicAPI.ref.setMaxSize.asFunction();

// getScreenInfoForWindow
typedef Int8 TGetScreenInfoForWindow(
    IntPtr window, Pointer<BDWScreenInfo> screenInfo);
typedef DGetScreenInfoForWindow = int Function(
    int window, Pointer<BDWScreenInfo> screenInfo);
final DGetScreenInfoForWindow _getScreenInfoForWindow =
    _publicAPI.ref.getScreenInfoForWindow.asFunction();

bool getScreenInfoNative(int window, Pointer<BDWScreenInfo> screenInfo) {
  int result = _getScreenInfoForWindow(window, screenInfo);
  return result == BDW_SUCCESS ? true : false;
}

// setPositionForWindow
typedef Int8 TSetPositionForWindow(IntPtr window, Pointer<BDWOffset> rect);
typedef DSetPositionForWindow = int Function(
    int window, Pointer<BDWOffset> rect);
final DSetPositionForWindow setPositionForWindowNative =
    _publicAPI.ref.setPositionForWindow.asFunction();

/// Shared scratch for the two-double out/in params, for the same reason as
/// `_scratchRect` in window_util.dart: these run per animation frame and inside
/// widget builds, and a calloc/free pair per call bought nothing. Synchronous
/// FFI that never re-enters Dart, main isolate only.
final Pointer<BDWOffset> _scratchOffset = newBDWOffset();

bool setPositionForWindow(int window, ui.Offset offset) {
  _scratchOffset.ref
    ..x = offset.dx
    ..y = offset.dy;
  int result = setPositionForWindowNative(window, _scratchOffset);
  return result == BDW_SUCCESS ? true : false;
}

// setRectForWindow
typedef Int8 TSetRectForWindow(IntPtr window, Pointer<BDWRect> rect);
typedef DSetRectForWindow = int Function(int window, Pointer<BDWRect> rect);
final DSetRectForWindow setRectForWindowNative =
    _publicAPI.ref.setRectForWindow.asFunction();

// getRectForWindow
typedef Int8 TGetRectForWindow(IntPtr window, Pointer<BDWRect> rect);
typedef DGetRectForWindow = int Function(int window, Pointer<BDWRect> rect);
final DGetRectForWindow getRectForWindowNative =
    _publicAPI.ref.getRectForWindow.asFunction();

// isWindowVisibleπ
typedef Int8 TIsWindowVisible(IntPtr window);
typedef DIsWindowVisible = int Function(int window);
final DIsWindowVisible _isWindowVisible =
    _publicAPI.ref.isWindowVisible.asFunction();
bool isWindowVisible(int window) =>
    _isWindowVisible(window) == 1 ? true : false;

// isWindowMaximized
typedef Int8 TIsWindowMaximized(IntPtr window);
typedef DIsWindowMaximized = int Function(int window);
final DIsWindowMaximized _isWindowMaximized =
    _publicAPI.ref.isWindowMaximized.asFunction();
bool isWindowMaximized(int window) =>
    _isWindowMaximized(window) == 1 ? true : false;

// maximizeWindow
typedef Void TMaximizeOrRestoreWindow(IntPtr window);
typedef DMaximizeOrRestoreWindow = void Function(int window);
final DMaximizeOrRestoreWindow maximizeOrRestoreWindow =
    _publicAPI.ref.maximizeOrRestoreWindow.asFunction();

// maximizeWindow
typedef Void TMaximizeWindow(IntPtr window);
typedef DMaximizeWindow = void Function(int window);
final DMaximizeWindow maximizeWindow =
    _publicAPI.ref.maximizeWindow.asFunction();

// toggleFullScreen
typedef Void TToggleFullScreen(IntPtr window);
typedef DToggleFullScreen = void Function(int window);
final DToggleFullScreen toggleFullScreenWindow =
    _publicAPI.ref.toggleFullScreen.asFunction();

// maximizeWindow
typedef Void TMinimizeWindow(IntPtr window);
typedef DMinimizeWindow = void Function(int window);
final DMinimizeWindow minimizeWindow =
    _publicAPI.ref.minimizeWindow.asFunction();

// closeWindow
typedef Void TCloseWindow(IntPtr window);
typedef DCloseWindow = void Function(int window);
final DCloseWindow closeWindow = _publicAPI.ref.closeWindow.asFunction();

// setWindowTitle
typedef Void TSetWindowTitle(IntPtr window, Pointer<Utf8> title);
typedef DSetWindowTitle = void Function(int window, Pointer<Utf8> title);
final DSetWindowTitle _setWindowTitle =
    _publicAPI.ref.setWindowTitle.asFunction();

void setWindowTitle(int window, String title) {
  final _title = title.toNativeUtf8();
  try {
    _setWindowTitle(window, _title);
  } finally {
    calloc.free(_title);
  }
}

// getTitleBarHeight
typedef Double TGetTitleBarHeight(IntPtr window);
typedef DGetTitleBarHeight = double Function(int window);
final DGetTitleBarHeight getTitleBarHeight =
    _publicAPI.ref.getTitleBarHeight.asFunction();

// getTitleBarButtonSize
typedef Int8 TGetTitleBarButtonSize(IntPtr window, Pointer<BDWOffset> size);
typedef DGetTitleBarButtonSize = int Function(
    int window, Pointer<BDWOffset> size);
final DGetTitleBarButtonSize _getTitleBarButtonSize =
    _publicAPI.ref.getTitleBarButtonSize.asFunction();
ui.Size getTitleBarButtonSize(int window) {
  // Called from WindowButton.build, which rebuilds on every hover state change,
  // so this used to allocate three times per title bar per hover frame.
  final result = _getTitleBarButtonSize(window, _scratchOffset);
  if (result != BDW_SUCCESS) {
    return ui.Size.zero;
  }
  return ui.Size(_scratchOffset.ref.x, _scratchOffset.ref.y);
}

// getWindowScaleFactor
typedef Double TGetWindowScaleFactor(IntPtr window);
typedef DGetWindowScaleFactor = double Function(int window);
final DGetWindowScaleFactor getWindowScaleFactor =
    _publicAPI.ref.getWindowScaleFactor.asFunction();

typedef Int8 TIsAlwaysOnTop(IntPtr window);
typedef DIsAlwaysOnTop = int Function(int window);
final DIsAlwaysOnTop _isAlwaysOnTop = _publicAPI.ref.isAlwaysOnTop.asFunction();
bool isAlwaysOnTop(int window) => _isAlwaysOnTop(window) == 1 ? true : false;

typedef Void TSetAlwaysOnTop(IntPtr window, Int8 value);
typedef DAlwaysOnTop = void Function(int window, int value);
final DAlwaysOnTop todoAlwaysOnTop = _publicAPI.ref.setAlwaysOnTop.asFunction();

// setBackgroundEffect
typedef Void TSetBackgroundEffect(IntPtr window, Int32 effect);
typedef DSetBackgroundEffect = void Function(int window, int effect);
final DSetBackgroundEffect setBackgroundEffect =
    _publicAPI.ref.setBackgroundEffect.asFunction();

// setTitleBarHeight
typedef Void TSetTitleBarHeight(IntPtr window, Int32 height);
typedef DSetTitleBarHeight = void Function(int window, int height);
final DSetTitleBarHeight setTitleBarHeight =
    _publicAPI.ref.setTitleBarHeight.asFunction();

// isPrimaryWindow
typedef Int8 TIsPrimaryWindow(IntPtr window);
typedef DIsPrimaryWindow = int Function(int window);
final DIsPrimaryWindow isPrimaryWindowNative =
    _publicAPI.ref.isPrimaryWindow.asFunction();
bool isPrimaryWindow(int window) =>
    isPrimaryWindowNative(window) == 1 ? true : false;

// terminateApp
typedef Void TTerminateApp();
typedef DTerminateApp = void Function();
final DTerminateApp terminateAppNative =
    _publicAPI.ref.terminateApp.asFunction();

// setWindowButtonVisibility
typedef Void TSetWindowButtonVisibility(
    IntPtr window, Int32 button, Int8 value);
typedef DSetWindowButtonVisibility = void Function(
    int window, int button, int value);
final DSetWindowButtonVisibility _setWindowButtonVisibility =
    _publicAPI.ref.setWindowButtonVisibility.asFunction();
void setWindowButtonVisibility(int window, int button, bool value) =>
    _setWindowButtonVisibility(window, button, value ? 1 : 0);

// setWindowButtonOffset
typedef Void TSetWindowButtonOffset(
    IntPtr window, Int32 button, Double x, Double y);
typedef DSetWindowButtonOffset = void Function(
    int window, int button, double x, double y);
final DSetWindowButtonOffset setWindowButtonOffset =
    _publicAPI.ref.setWindowButtonOffset.asFunction();

final class BDWPublicAPI extends Struct {
  external Pointer<NativeFunction<TGetAppWindow>> getAppWindow;
  external Pointer<NativeFunction<TSetWindowCanBeShown>> setWindowCanBeShown;
  external Pointer<NativeFunction<TSetInsideDoWhenWindowReady>>
      setInsideDoWhenWindowReady;
  external Pointer<NativeFunction<TShowWindow>> showWindow;
  external Pointer<NativeFunction<THideWindow>> hideWindow;
  external Pointer<NativeFunction<TMoveWindow>> moveWindow;
  external Pointer<NativeFunction<TSetSize>> setSize;
  external Pointer<NativeFunction<TSetMinSize>> setMinSize;
  external Pointer<NativeFunction<TSetMaxSize>> setMaxSize;
  external Pointer<NativeFunction<TGetScreenInfoForWindow>>
      getScreenInfoForWindow;
  external Pointer<NativeFunction<TSetPositionForWindow>> setPositionForWindow;
  external Pointer<NativeFunction<TSetRectForWindow>> setRectForWindow;
  external Pointer<NativeFunction<TGetRectForWindow>> getRectForWindow;
  external Pointer<NativeFunction<TIsWindowVisible>> isWindowVisible;
  external Pointer<NativeFunction<TIsWindowMaximized>> isWindowMaximized;
  external Pointer<NativeFunction<TMaximizeOrRestoreWindow>>
      maximizeOrRestoreWindow;
  external Pointer<NativeFunction<TMaximizeWindow>> maximizeWindow;
  external Pointer<NativeFunction<TToggleFullScreen>> toggleFullScreen;
  external Pointer<NativeFunction<TMinimizeWindow>> minimizeWindow;
  external Pointer<NativeFunction<TCloseWindow>> closeWindow;
  external Pointer<NativeFunction<TSetWindowTitle>> setWindowTitle;
  external Pointer<NativeFunction<TGetTitleBarHeight>> getTitleBarHeight;
  external Pointer<NativeFunction<TGetTitleBarButtonSize>>
      getTitleBarButtonSize;
  external Pointer<NativeFunction<TGetWindowScaleFactor>> getWindowScaleFactor;

  external Pointer<NativeFunction<TSetAlwaysOnTop>> setAlwaysOnTop;
  external Pointer<NativeFunction<TIsAlwaysOnTop>> isAlwaysOnTop;
  external Pointer<NativeFunction<TSetBackgroundEffect>> setBackgroundEffect;
  external Pointer<NativeFunction<TSetTitleBarHeight>> setTitleBarHeight;
  external Pointer<NativeFunction<TIsPrimaryWindow>> isPrimaryWindow;
  external Pointer<NativeFunction<TTerminateApp>> terminateApp;
  external Pointer<NativeFunction<TSetWindowButtonVisibility>>
      setWindowButtonVisibility;
  external Pointer<NativeFunction<TSetWindowButtonOffset>>
      setWindowButtonOffset;
}

final class BDWAPI extends Struct {
  external Pointer<BDWPublicAPI> publicAPI;
}

typedef Pointer<BDWAPI> TBitsdojoWindowAPI();

final TBitsdojoWindowAPI bitsdojoWindowAPI = _appExecutable
    .lookup<NativeFunction<TBitsdojoWindowAPI>>("bitsdojo_window_api")
    .asFunction();

final Pointer<BDWPublicAPI> _publicAPI = bitsdojoWindowAPI().ref.publicAPI;

typedef TSetHasShadow = Void Function(IntPtr window, Int8 value);
typedef DSetHasShadow = void Function(int window, int value);
final DSetHasShadow setHasShadowNative = _appExecutable
    .lookup<NativeFunction<TSetHasShadow>>("setHasShadow")
    .asFunction();

typedef TIsHasShadow = Int8 Function(IntPtr window);
typedef DIsHasShadow = int Function(int window);
final DIsHasShadow isHasShadowNative = _appExecutable
    .lookup<NativeFunction<TIsHasShadow>>("isHasShadow")
    .asFunction();
