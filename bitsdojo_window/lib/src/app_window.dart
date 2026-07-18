import 'dart:io' show Platform;

import 'package:bitsdojo_window_linux/bitsdojo_window_linux.dart';
import 'package:bitsdojo_window_macos/bitsdojo_window_macos.dart';
import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:bitsdojo_window_platform_interface/method_channel_bitsdojo_window.dart';
import 'package:bitsdojo_window_windows/bitsdojo_window_windows.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

bool _platformInstanceNeedsInit = true;

DesktopWindowCapabilities get platformWindowCapabilities {
  if (kIsWeb) {
    return const DesktopWindowCapabilities();
  }

  if (Platform.isWindows) {
    return const DesktopWindowCapabilities(
      supportsBackgroundEffects: true,
    );
  }

  if (Platform.isMacOS) {
    return const DesktopWindowCapabilities(
      supportsBackgroundEffects: true,
      supportsTitleBarButtonVisibility: true,
      supportsTitleBarButtonOffset: true,
    );
  }

  if (Platform.isLinux) {
    return const DesktopWindowCapabilities(
      supportsTitleBarButtonVisibility: true,
    );
  }

  return const DesktopWindowCapabilities();
}

void initPlatformInstance() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    if (BitsdojoWindowPlatform.instance is MethodChannelBitsdojoWindow) {
      if (Platform.isWindows) {
        BitsdojoWindowPlatform.instance = BitsdojoWindowWindows();
      } else if (Platform.isMacOS) {
        BitsdojoWindowPlatform.instance = BitsdojoWindowMacOS();
      } else if (Platform.isLinux) {
        BitsdojoWindowPlatform.instance = BitsdojoWindowLinux();
      }
    }
  } else {
    BitsdojoWindowPlatform.instance = BitsdojoWindowPlatformNotImplemented();
  }
}

BitsdojoWindowPlatform get _platform {
  var needsInit = _platformInstanceNeedsInit;
  if (needsInit) {
    initPlatformInstance();
    _platformInstanceNeedsInit = false;
  }
  return BitsdojoWindowPlatform.instance;
}

void doWhenWindowReady(VoidCallback callback) {
  _platform.doWhenWindowReady(callback);
}

DesktopWindow get appWindow {
  return _platform.appWindow;
}

DesktopWindow getWindowForHandle(int handle) {
  return _platform.getWindowForHandle(handle);
}

void terminateApp() {
  _platform.terminateApp();
}
