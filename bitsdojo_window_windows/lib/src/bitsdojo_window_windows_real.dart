import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'dart:async';
import 'dart:convert';

import './window.dart';
import './native_api.dart';

export './window_interface.dart';

class BitsdojoWindowWindows extends BitsdojoWindowPlatform {
  static const MethodChannel _channel = MethodChannel('bitsdojo/window');
  final _windows = <int, WinWindow>{};
  final _readyCallbacks = <VoidCallback>[];
  int? _handle;
  bool _firstFrameRasterized = false;
  bool _didStartReadyWait = false;
  bool _identitySeeded = false;
  late final WinWindow _appWindow;

  @override
  void seedWindowIdentity({
    String? name,
    Map<String, dynamic>? arguments,
    bool? isMainWindow,
  }) {
    _identitySeeded = true;
    if (name != null) _appWindow.name = name;
    if (arguments != null) _appWindow.arguments = arguments;
    if (isMainWindow != null) _appWindow.isMainWindow = isMainWindow;
  }

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
      _applyWindowInfo(call.arguments);
    } else if (call.method == 'windowEvent') {
      final arguments = call.arguments as Map?;
      if (arguments == null) return;
      final event = decodeWindowEvent(arguments);
      if (event == null) return;
      final handle = arguments['handle'] as int?;
      final window = handle != null ? getWindowForHandle(handle) : appWindow;
      window.emitWindowEvent(event);
    } else if (call.method == 'windowClosed') {
      final arguments = call.arguments as Map?;
      final name = arguments?['name'] as String?;
      if (name != null) {
        // The hub fans out: openDialog futures, the windowClosed stream, and
        // the legacy onWindowClosed callback.
        WindowCloseHub.notifyClosed(name, arguments?['result'] as String?);
      }
    } else if (call.method == 'updateArguments') {
      final argumentsString = call.arguments as String?;
      if (argumentsString != null) {
        try {
          final newArgs = jsonDecode(argumentsString) as Map<String, dynamic>;
          _appWindow.arguments = newArgs;
          _appWindow.notifyWindowChanged();
          if (_appWindow.onArgumentsChanged != null) {
            _appWindow.onArgumentsChanged!();
          }
        } catch (e, st) {
          debugPrint("bitsdojo_window: error updating window arguments: $e\n$st");
        }
      }
    }
  }

  /// Adopt this engine's window identity, from either delivery path: the
  /// native `windowReady` push, or the Dart-initiated `getWindowInfo` pull.
  void _applyWindowInfo(dynamic info) {
    if (info is! Map) return;
    final handle = info['handle'] as int?;
    if (handle == null) return;

    _handle = handle;
    final name = info['name'] as String?;
    final argumentsString = info['arguments'] as String?;

    final isPrimary = info['isPrimary'] as bool?;
    if (isPrimary != null) {
      _appWindow.isMainWindow = isPrimary;
    }

    _appWindow.handle = handle;
    if (name != null) {
      _appWindow.name = name;
    }
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

    _appWindow.notifyWindowChanged();
    if (_appWindow.onArgumentsChanged != null) {
      _appWindow.onArgumentsChanged!();
    }
  }

  bool _requestedWindowInfo = false;

  /// Ask the native side which window this engine owns.
  ///
  /// The `windowReady` push fires during plugin registration — before this
  /// handler exists — so it can be lost. The pull cannot: by the time Dart
  /// code runs, the native side has long since captured the identity on the
  /// plugin instance. Old native builds without `getWindowInfo` throw
  /// MissingPluginException / PlatformException; both fall back to the
  /// pre-existing paths.
  Future<void> _requestWindowInfo() async {
    if (_requestedWindowInfo || _handle != null) return;
    _requestedWindowInfo = true;
    try {
      final info = await _channel.invokeMethod<dynamic>('getWindowInfo');
      if (_handle == null) _applyWindowInfo(info);
    } catch (_) {
      // Older native side: rely on windowReady / getAppWindow as before.
    }
  }

  @override
  void doWhenWindowReady(VoidCallback callback) {
    _readyCallbacks.add(callback);
    _ensureReadyWaitStarted();
    unawaited(_requestWindowInfo());
    _refreshHandleFromNative();
    _flushReadyCallbacks();
  }

  void _ensureReadyWaitStarted() {
    if (_didStartReadyWait) return;
    _didStartReadyWait = true;
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((value) {
      _firstFrameRasterized = true;
      unawaited(_requestWindowInfo());
      _refreshHandleFromNative();
      _flushReadyCallbacks();
    });
  }

  void _refreshHandleFromNative() {
    if (_handle != null) return;
    // The native getAppWindow() global names whichever window attached LAST,
    // so in a multi-window app a secondary engine must never trust it: it
    // would adopt another window's handle and unlock that window's
    // can-be-shown gate while its own stayed hidden. A window whose identity
    // was seeded as secondary waits for windowReady/getWindowInfo instead.
    if (_identitySeeded && !_appWindow.isMainWindow) return;
    final handle = getAppWindow();
    if (handle == 0) return;

    _handle = handle;
    if (!_identitySeeded) {
      _appWindow.isMainWindow = true;
    }
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
    WindowModality modality = WindowModality.none,
  }) async {
    await _channel.invokeMethod('openNewWindow', {
      'name': name,
      'width': size?.width,
      'height': size?.height,
      'x': position?.dx,
      'y': position?.dy,
      'arguments': arguments != null ? jsonEncode(arguments) : null,
      // Omitted for none: an older runner ignores the key either way, and
      // the default case keeps the wire identical to pre-modality versions.
      if (modality != WindowModality.none) 'modality': modality.name,
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
