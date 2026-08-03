import 'dart:convert' show jsonDecode;
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

const _bdwNamePrefix = '--bdw-name=';
const _bdwArgsPrefix = '--bdw-args=';

/// Returns [args] without the `--bdw-*` identity arguments that the native
/// side injects for secondary windows. Use this before handing main's args
/// to your own argument parser (strict parsers would reject them).
List<String> withoutWindowIdentityArgs(List<String> args) =>
    args.where((arg) => !arg.startsWith('--bdw-')).toList();

/// Seeds this window's identity from the engine's dart entrypoint arguments
/// (`main(List<String> args)`), so `window.name` / `window.arguments` are
/// available synchronously — before the first widget build — instead of
/// waiting for the native `windowReady` message. Secondary windows created
/// by the native side pass `--bdw-name=<name>` and `--bdw-args=<json>`.
void seedWindowIdentityFromArgs(List<String> args) {
  String? name;
  Map<String, dynamic>? arguments;
  for (final arg in args) {
    if (arg.startsWith(_bdwNamePrefix)) {
      name = arg.substring(_bdwNamePrefix.length);
    } else if (arg.startsWith(_bdwArgsPrefix)) {
      try {
        arguments = jsonDecode(arg.substring(_bdwArgsPrefix.length))
            as Map<String, dynamic>;
      } catch (_) {
        // Malformed JSON: fall back to the windowReady channel message.
      }
    }
  }
  if (name == null && arguments == null) return;
  _platform.seedWindowIdentity(
    name: name,
    arguments: arguments,
    isMainWindow: false,
  );
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
