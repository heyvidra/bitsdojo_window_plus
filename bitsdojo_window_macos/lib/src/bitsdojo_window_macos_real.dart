library bitsdojo_window_macos;

import 'dart:convert';

import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import './native_api.dart';
import './window.dart';

class BitsdojoWindowMacOS extends BitsdojoWindowPlatform {
  static const MethodChannel _channel = MethodChannel('bitsdojo/window');

  final Map<int, MacOSWindow> _windows = {};
  int? _handle;
  late final MacOSWindow _appWindow;

  final List<VoidCallback> _pendingCallbacks = [];
  bool _isWindowReady = false;

  BitsdojoWindowMacOS() : super() {
    _channel.setMethodCallHandler(_handleMethodCall);
    _appWindow = MacOSWindow();
  }

  @override
  void seedWindowIdentity({
    String? name,
    Map<String, dynamic>? arguments,
    bool? isMainWindow, // ignored: macOS queries this per-handle natively
  }) {
    if (name != null) _appWindow.name = name;
    if (arguments != null) _appWindow.arguments = arguments;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'closeRequested') {
      final handle = call.arguments['handle'] as int?;
      if (handle == null) return;
      final window = getWindowForHandle(handle) as MacOSWindow;
      if (window.onClose != null) {
        window.onClose!();
      } else {
        window.close();
      }
    } else if (call.method == 'windowReady') {
      final handle = call.arguments['handle'] as int?;
      if (handle != null) {
        _handle = handle;
        final depth = call.arguments['depth'] as int? ?? 0;
        final name = call.arguments['name'] as String?;
        final arguments =
            (call.arguments['arguments'] as Map?)?.cast<String, dynamic>();

        _appWindow.handle = handle;
        _appWindow.depth = depth;
        if (name != null) {
          _appWindow.name = name;
        }
        if (arguments != null) {
          _appWindow.arguments = arguments;
        }
        _windows[handle] = _appWindow;

        _isWindowReady = true;

        for (final callback in _pendingCallbacks) {
          _ready(handle, callback);
        }
        _pendingCallbacks.clear();

        _appWindow.notifyWindowChanged();
        if (_appWindow.onArgumentsChanged != null) {
          _appWindow.onArgumentsChanged!();
        }
      }
    } else if (call.method == 'windowClosed') {
      final name = call.arguments['name'] as String?;
      if (name != null) {
        onWindowClosed?.call(name);
      }
    } else if (call.method == 'argumentsChanged') {
      if (_handle != null) {
        final arguments =
            (call.arguments['arguments'] as Map?)?.cast<String, dynamic>();
        final window = getWindowForHandle(_handle!) as MacOSWindow;
        window.arguments = arguments;
        window.notifyWindowChanged();
        if (window.onArgumentsChanged != null) {
          window.onArgumentsChanged!();
        }
      }
    }
  }

  void _ready(int handle, VoidCallback callback) {
    setWindowCanBeShown(handle, true);
    setInsideDoWhenWindowReady(true);
    callback();
    setInsideDoWhenWindowReady(false);
  }

  @override
  void doWhenWindowReady(VoidCallback callback) {
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((value) {
      if (_isWindowReady && _handle != null) {
        _ready(_handle!, callback);
      } else {
        _pendingCallbacks.add(callback);
      }
    });
  }

  @override
  void dragAppWindow() async {}

  @override
  DesktopWindow getWindowForHandle(int handle) {
    return _windows.putIfAbsent(handle, () => MacOSWindow(handle));
  }

  @override
  DesktopWindow get appWindow {
    if (_handle == null) {
      final handle = getAppWindow();
      if (handle != 0) {
        _handle = handle;
        _appWindow.handle = handle;
        _windows[handle] = _appWindow;
      }
    }
    return _appWindow;
  }

  @override
  bool isMainWindow(int handle) {
    if (handle == 0) return false;
    return isPrimaryWindow(handle);
  }

  @override
  void terminateApp() {
    terminateAppNative();
  }

  @override
  Future<void> openNewWindow({
    String? name,
    Size? size,
    Offset? position,
    Map<String, dynamic>? arguments,
  }) async {
    await _channel.invokeMethod('openNewWindow', {
      'name': name,
      'width': size?.width,
      'height': size?.height,
      'x': position?.dx,
      'y': position?.dy,
      'arguments': arguments,
      // Pre-encoded on the Dart side so the native layer can pass it through
      // to --bdw-args verbatim. Re-encoding the codec Map with
      // NSJSONSerialization would turn 1.0 into "1", flipping double->int
      // when the child engine decodes it.
      'argumentsJson': arguments != null ? jsonEncode(arguments) : null,
    });
  }

  @override
  Future<bool> hasWindow(String name) async {
    return await _channel.invokeMethod<bool>('hasWindow', {'name': name}) ??
        false;
  }

  @override
  Future<void> closeWindow(String name) async {
    await _channel.invokeMethod('closeWindow', {'name': name});
  }
}
