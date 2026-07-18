library bitsdojo_window_linux;

import 'dart:convert';
import 'package:flutter/services.dart';

import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
export './window.dart';
import './window.dart';
import 'package:flutter/widgets.dart';

import './native_api.dart';

T? _ambiguate<T>(T? value) => value;

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
      } else if (call.method == 'updateArguments') {
        final argumentsString = call.arguments as String?;
        if (argumentsString != null) {
          try {
            final newArgs = jsonDecode(argumentsString) as Map<String, dynamic>;
            final window = appWindow as GtkWindow;
            window.arguments = newArgs;
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
    _ambiguate(WidgetsBinding.instance)!
        .waitUntilFirstFrameRasterized
        .then((value) {
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
}
