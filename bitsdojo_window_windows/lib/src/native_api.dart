library bitsdojo_window_windows;

import 'dart:ffi';

final DynamicLibrary _appExecutable = DynamicLibrary.executable();

// isBitsdojoWindowLoaded
typedef Int8 TIsBitsdojoWindowLoaded();
typedef DTIsBitsdojoWindowLoaded = int Function();
final DTIsBitsdojoWindowLoaded? _isBitsdojoWindowLoaded =
    _publicAPI.ref.isBitsdojoWindowLoaded.asFunction();

bool isBitsdojoWindowLoaded() {
  if (_isBitsdojoWindowLoaded == null) {
    return false;
  }
  return _isBitsdojoWindowLoaded!() == 1 ? true : false;
}

// getAppWindow
typedef IntPtr TGetAppWindow();
typedef DGetAppWindow = int Function();
final DGetAppWindow getAppWindow = _publicAPI.ref.getAppWindow.asFunction();

// isDPIAware
typedef Int8 TIsDPIAware();
typedef DIsDPIAware = int Function();
final DIsDPIAware _isDPIAware = _publicAPI.ref.isDPIAware.asFunction();
bool isDPIAware() => _isDPIAware() != 0;

// setWindowCanBeShown
typedef Void TSetWindowCanBeShown(IntPtr window, Int8 value);
typedef DSetWindowCanBeShown = void Function(int window, int value);
final DSetWindowCanBeShown _setWindowCanBeShown =
    _publicAPI.ref.setWindowCanBeShown.asFunction();
void setWindowCanBeShown(int handle, bool value) =>
    _setWindowCanBeShown(handle, value ? 1 : 0);

// setMinSize
typedef Void TSetMinSize(IntPtr window, Int32 width, Int32 height);
typedef DSetMinSize = void Function(int window, int width, int height);
final DSetMinSize setMinSize = _publicAPI.ref.setMinSize.asFunction();

// setMaxSize
typedef Void TSetMaxSize(IntPtr window, Int32 width, Int32 height);
typedef DSetMaxSize = void Function(int window, int width, int height);
final DSetMaxSize setMaxSize = _publicAPI.ref.setMaxSize.asFunction();

// setWindowCutOnMaximize
typedef Void TSetWindowCutOnMaximize(IntPtr window, Int32 width);
typedef DSetWindowCutOnMaximize = void Function(int window, int width);
final DSetWindowCutOnMaximize setWindowCutOnMaximize =
    _publicAPI.ref.setWindowCutOnMaximize.asFunction();

typedef Int8 TIsAlwaysOnTop(IntPtr window);
typedef DIsAlwaysOnTop = int Function(int window);
final DIsAlwaysOnTop _isAlwaysOnTop = _publicAPI.ref.isAlwaysOnTop.asFunction();
bool isAlwaysOnTop(int handle) => _isAlwaysOnTop(handle) == 1;

typedef Void TSetAlwaysOnTop(IntPtr window, Int8 value);
typedef DAlwaysOnTop = void Function(int window, int value);
final DAlwaysOnTop setAlwaysOnTop = _publicAPI.ref.setAlwaysOnTop.asFunction();

final class BDWPublicAPI extends Struct {
  external Pointer<NativeFunction<TIsBitsdojoWindowLoaded>>
      isBitsdojoWindowLoaded;
  external Pointer<NativeFunction<TGetAppWindow>> getAppWindow;
  external Pointer<NativeFunction<TSetWindowCanBeShown>> setWindowCanBeShown;
  external Pointer<NativeFunction<TSetMinSize>> setMinSize;
  external Pointer<NativeFunction<TSetMaxSize>> setMaxSize;
  external Pointer<NativeFunction<TSetWindowCutOnMaximize>>
      setWindowCutOnMaximize;
  external Pointer<NativeFunction<TIsDPIAware>> isDPIAware;

  external Pointer<NativeFunction<TIsAlwaysOnTop>> isAlwaysOnTop;
  external Pointer<NativeFunction<TSetAlwaysOnTop>> setAlwaysOnTop;
  external Pointer<NativeFunction<Void Function(IntPtr, Pointer)>>
      setCloseRequestedCallback;
  external Pointer<NativeFunction<TSetBackgroundEffect>> setBackgroundEffect;
}

// setCloseRequestedCallback
typedef Void TSetCloseRequestedCallback(IntPtr window, Pointer callback);
typedef DSetCloseRequestedCallback = void Function(
    int window, Pointer callback);
final DSetCloseRequestedCallback setCloseRequestedCallback =
    _publicAPI.ref.setCloseRequestedCallback.asFunction();

// setBackgroundEffect
typedef Void TSetBackgroundEffect(IntPtr window, Int32 effect);
typedef DSetBackgroundEffect = void Function(int window, int effect);
final DSetBackgroundEffect setBackgroundEffect =
    _publicAPI.ref.setBackgroundEffect.asFunction();

final class BDWAPI extends Struct {
  external Pointer<BDWPublicAPI> publicAPI;
}

typedef Pointer<BDWAPI> TBitsdojoWindowAPI();

final TBitsdojoWindowAPI bitsdojoWindowAPI = _appExecutable
    .lookup<NativeFunction<TBitsdojoWindowAPI>>("bitsdojo_window_api")
    .asFunction();

final Pointer<BDWPublicAPI> _publicAPI = bitsdojoWindowAPI().ref.publicAPI;
