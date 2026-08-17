import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bitsdojo_window_platform_interface.dart';

const MethodChannel _channel = MethodChannel('bitsdojo/window');

/// An implementation of [BitsdojoWindowPlatform] that uses method channels.
class MethodChannelBitsdojoWindow extends BitsdojoWindowPlatform {
  @override
  void dragAppWindow() async {
    try {
      await _channel.invokeMethod('dragAppWindow');
    } catch (e, st) {
      debugPrint("bitsdojo_window: could not start dragging: $e\n$st");
    }
  }

  @override
  Future<int> showNativeAlert({
    required String title,
    String? message,
    List<String> buttons = const ['OK'],
    NativeAlertStyle style = NativeAlertStyle.info,
  }) async {
    try {
      return await _channel.invokeMethod<int>('showNativeAlert', {
            'title': title,
            'message': message,
            'buttons': buttons,
            'style': style.index,
          }) ??
          -1;
    } catch (e, st) {
      // Same shape as a dismissed alert: a caller branching on the returned
      // index shouldn't have to also handle an exception on a platform
      // without native alerts (web, tests).
      debugPrint("bitsdojo_window: could not show native alert: $e\n$st");
      return -1;
    }
  }

  @override
  Future<String?> showNativeMenu(
    List<NativeMenuItem> items, {
    Offset? position,
  }) async {
    try {
      return await _channel.invokeMethod<String>('showNativeMenu', {
        'items': [for (final item in items) item.toMap()],
        'x': position?.dx,
        'y': position?.dy,
      });
    } catch (e, st) {
      debugPrint("bitsdojo_window: could not show native menu: $e\n$st");
      return null;
    }
  }
}
