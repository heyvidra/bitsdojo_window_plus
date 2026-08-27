library bitsdojo_window_linux;

import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:flutter/services.dart';

import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
export './window.dart';
import './window.dart';
import 'package:flutter/widgets.dart';

import './native_api.dart';

class BitsdojoWindowLinux extends BitsdojoWindowPlatform {
  static const MethodChannel _channel = MethodChannel('bitsdojo/window');
  final _windows = <int, GtkWindow>{};

  @override
  DesktopWindow getWindowForHandle(int handle) {
    return _windows.putIfAbsent(handle, () => GtkWindow(handle));
  }

  BitsdojoWindowLinux() : super() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'closeRequested') {
        int? handle = call.arguments as int?;
        final window = (handle != null ? getWindowForHandle(handle) : appWindow)
            as GtkWindow;
        if (window.onClose != null) {
          window.onClose!();
        } else {
          window.close();
        }
      } else if (call.method == 'windowEvent') {
        final arguments = call.arguments as Map?;
        if (arguments == null) return;
        final event = decodeWindowEvent(arguments);
        if (event == null) return;
        final handle = arguments['handle'] as int?;
        final window = handle != null ? getWindowForHandle(handle) : appWindow;
        window.emitWindowEvent(event);
      } else if (call.method == 'windowClosed') {
        // Sent by the parent-process child-exit watch: on Linux every window
        // is its own process, so only windows THIS window spawned are
        // reported (documented ceiling of the one-process-per-window model).
        final arguments = call.arguments as Map?;
        final name = arguments?['name'] as String?;
        if (name != null) {
          WindowCloseHub.notifyClosed(name, arguments?['result'] as String?);
        }
      } else if (call.method == 'updateArguments') {
        final argumentsString = call.arguments as String?;
        if (argumentsString != null) {
          try {
            final newArgs = jsonDecode(argumentsString) as Map<String, dynamic>;
            final window = appWindow as GtkWindow;
            window.arguments = newArgs;
            window.notifyWindowChanged();
            if (window.onArgumentsChanged != null) {
              window.onArgumentsChanged!();
            }
          } catch (e, st) {
            debugPrint(
                "bitsdojo_window: error updating window arguments: $e\n$st");
          }
        }
      }
    });
  }

  static void registerWith() {
    BitsdojoWindowPlatform.instance = BitsdojoWindowLinux();
  }

  @override
  void doWhenWindowReady(VoidCallback callback) {
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((value) {
      isInsideDoWhenWindowReady = true;
      callback();
      isInsideDoWhenWindowReady = false;
    });
  }

  @override
  DesktopWindow get appWindow {
    final handle = getAppWindowHandle();
    return getWindowForHandle(handle);
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
  Future<void> setWindowResult(String resultJson) async {
    // One process per window: the parent set BDW_RESULT_FILE when it spawned
    // this dialog, and reads the file back when this process exits. Writing
    // it from Dart keeps the child side of the result channel native-free.
    // Absent env (not a dialog, or an old parent) → nobody is awaiting.
    final path = Platform.environment['BDW_RESULT_FILE'];
    if (path == null || path.isEmpty) return;
    try {
      File(path).writeAsStringSync(resultJson);
    } catch (e, st) {
      debugPrint("bitsdojo_window: could not write window result: $e\n$st");
    }
  }

  @override
  void setAlwaysOnTop(bool onTop) {
    _channel.invokeMethod('setAlwaysOnTop', onTop);
  }

  @override
  void setBackgroundEffect(WindowEffect effect) {
    _channel.invokeMethod('setBackgroundEffect', effect.index);
  }

  @override
  void setWindowTitleBarButtonVisibility(
      DesktopWindowButton button, bool visible) {
    _channel.invokeMethod('setWindowTitleBarButtonVisibility', {
      'button': button.index,
      'visible': visible,
    });
  }

  // Linux "multi-window" launches a separate PROCESS per window (BDW_* env
  // vars) — there is no in-process registry to query or close through, so
  // these degrade to their documented defaults.
  @override
  Future<bool> hasWindow(String name) async => false;

  @override
  Future<void> closeWindow(String name) async {}
}
