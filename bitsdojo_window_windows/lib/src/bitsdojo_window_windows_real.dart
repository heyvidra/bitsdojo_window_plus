import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'dart:convert';

import './window.dart';
import './native_api.dart';

export './window_interface.dart';

T? _ambiguate<T>(T? value) => value;

class BitsdojoWindowWindows extends BitsdojoWindowPlatform {
  static const MethodChannel _channel = MethodChannel('bitsdojo/window');
  final _windows = <int, WinWindow>{};
  final _readyCallbacks = <VoidCallback>[];
  int? _handle;
  bool _firstFrameRasterized = false;
  bool _didStartReadyWait = false;
  late final WinWindow _appWindow;

  @override
  DesktopWindow getWindowForHandle(int handle) {
    return _windows.putIfAbsent(handle, () => WinWindow(handle));
  }

  BitsdojoWindowWindows() : super() {
    _channel.setMethodCallHandler(_handleMethodCall);
    _appWindow = WinWindow();
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'closeRequested') {
      int? handle = call.arguments as int?;
      final window = (handle != null ? getWindowForHandle(handle) : appWindow)
          as WinWindow;
      if (window.onClose != null) {
        window.onClose!();
      } else {
        window.close();
      }
    } else if (call.method == 'windowReady') {
      final handle = call.arguments['handle'] as int?;
      if (handle != null) {
        _handle = handle;
        final name = call.arguments['name'] as String?;
        final argumentsString = call.arguments['arguments'] as String?;

        final isPrimary = call.arguments['isPrimary'] as bool?;
        if (isPrimary != null) {
          _appWindow.isMainWindow = isPrimary;
        }

        _appWindow.handle = handle;
        _appWindow.name = name;
        if (argumentsString != null) {
          try {
            _appWindow.arguments =
                jsonDecode(argumentsString) as Map<String, dynamic>;
          } catch (e, st) {
            debugPrint("bitsdojo_window: error decoding window arguments: $e\n$st");
          }
        }

        _windows[handle] = _appWindow;
        _flushReadyCallbacks();

        if (_appWindow.onArgumentsChanged != null) {
          _appWindow.onArgumentsChanged!();
        }
      }
    } else if (call.method == 'updateArguments') {
      final argumentsString = call.arguments as String?;
      if (argumentsString != null) {
        try {
          final newArgs = jsonDecode(argumentsString) as Map<String, dynamic>;
          _appWindow.arguments = newArgs;
          if (_appWindow.onArgumentsChanged != null) {
            _appWindow.onArgumentsChanged!();
          }
        } catch (e, st) {
          debugPrint("bitsdojo_window: error updating window arguments: $e\n$st");
        }
      }
    }
  }

  @override
  void doWhenWindowReady(VoidCallback callback) {
    _readyCallbacks.add(callback);
    _ensureReadyWaitStarted();
    _refreshHandleFromNative();
    _flushReadyCallbacks();
  }

  void _ensureReadyWaitStarted() {
    if (_didStartReadyWait) return;
    _didStartReadyWait = true;
    _ambiguate(WidgetsBinding.instance)!
        .waitUntilFirstFrameRasterized
        .then((value) {
      _firstFrameRasterized = true;
      _refreshHandleFromNative();
      _flushReadyCallbacks();
    });
  }

  void _refreshHandleFromNative() {
    if (_handle != null) return;
    final handle = getAppWindow();
    if (handle == 0) return;

    _handle = handle;
    _appWindow.isMainWindow = true;
    _appWindow.handle = handle;
    _windows[handle] = _appWindow;
  }

  void _flushReadyCallbacks() {
    if (!_firstFrameRasterized || _handle == null || _readyCallbacks.isEmpty) {
      return;
    }

    final handle = _handle!;
    final callbacks = List<VoidCallback>.from(_readyCallbacks);
    _readyCallbacks.clear();

    for (final callback in callbacks) {
      isInsideDoWhenWindowReady = true;
      setWindowCanBeShown(handle, true);
      callback();
      isInsideDoWhenWindowReady = false;
    }
  }

  @override
  DesktopWindow get appWindow {
    if (_handle == null) {
      _refreshHandleFromNative();
    }
    return _appWindow;
  }

  @override
  void terminateApp() {
    _channel.invokeMethod('terminateApp');
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
      'arguments': arguments != null ? jsonEncode(arguments) : null,
    });
  }
}
