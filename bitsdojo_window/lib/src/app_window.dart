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

/// This engine's own window.
///
/// ## The shape of the API
///
/// Every call has exactly one home, decided by what it acts on: THIS window
/// is a member here — `appWindow.close()`, `appWindow.showNativeAlert(...)`,
/// `appWindow.openDialog(...)` — and the process or the machine is a member
/// of [desktopApp]: `desktopApp.closeWindow(name)`, `desktopApp.displays()`,
/// `desktopApp.terminate()`. There are no other top-level functions; the
/// bootstrap family (`runBitsdojoWindowApp`, `doWhenWindowReady`, ...) is the
/// one exemption, because it runs before the objects mean anything.
///
/// ## Sync or async
///
/// Acting on this window is synchronous and fire-and-forget: `close`,
/// `minimize`, `maximize`, `restore`, `show`, `hide`, `startDragging` all
/// return void. There is nothing to await — the platform is told, and the
/// result arrives (if at all) as a [DesktopWindow.events] event.
///
/// Anything crossing a boundary — another window, a new process, the user —
/// returns a Future: `openNewWindow`, `openDialog`, `animateTo`, the
/// native-UI calls, and everything on [desktopApp]. `await appWindow.close()`
/// does not compile, and that asymmetry with
/// `await desktopApp.closeWindow(name)` is the rule above, not an oversight.
DesktopWindow get appWindow {
  return _platform.appWindow;
}

/// Process- and machine-level operations — everything that does not act on
/// one particular window. The other half of the API lives on [appWindow].
class DesktopApp {
  const DesktopApp._();

  /// Whether a window opened under [name] currently exists anywhere in the
  /// process. False on platforms without multi-window support.
  Future<bool> hasWindow(String name) => _platform.hasWindow(name);

  /// Closes the window opened under [name]. A no-op when no such window
  /// exists — unlike re-calling `openNewWindow` with a dismiss payload, this
  /// can never summon a window just to close it.
  Future<void> closeWindow(String name) => _platform.closeWindow(name);

  /// Names of windows that closed, however they closed. Broadcast — listen
  /// from as many places as needed. Process-wide on Windows and macOS; on
  /// Linux — one process per window — only windows this window spawned are
  /// reported. A window never hears about its own close (its engine dies
  /// with it).
  Stream<String> get windowClosed => WindowCloseHub.closed;

  /// The monitors attached to the machine, in no guaranteed order. Empty when
  /// the platform can't enumerate them.
  ///
  /// [Display.bounds] and [Display.workArea] are in the same units and origin
  /// as `appWindow.position` on the same platform, so placing a window on a
  /// chosen display is direct:
  ///
  /// ```dart
  /// final display =
  ///     (await desktopApp.displays()).firstWhere((d) => !d.isPrimary);
  /// appWindow.position = display.workArea.topLeft;
  /// ```
  ///
  /// Those units are logical pixels on macOS and Linux, and device pixels on
  /// Windows — matching what `position` reads and writes there. Use
  /// [Display.logicalBounds] for logical pixels on every platform.
  Future<List<Display>> displays() => _platform.getDisplays();

  /// Terminates the application.
  void terminate() => _platform.terminateApp();

  /// A [DesktopWindow] proxy for a raw native handle. Escape hatch; most
  /// windows are better addressed by name via [WindowRef] or [closeWindow].
  DesktopWindow windowForHandle(int handle) =>
      _platform.getWindowForHandle(handle);
}

/// The process/machine half of the API; see [appWindow] for the shape rule.
const DesktopApp desktopApp = DesktopApp._();

@Deprecated('use desktopApp.hasWindow(name)')
Future<bool> hasWindow(String name) => desktopApp.hasWindow(name);

@Deprecated('use desktopApp.closeWindow(name)')
Future<void> closeWindow(String name) => desktopApp.closeWindow(name);

/// Legacy single-slot form of [DesktopApp.windowClosed]. Still fires (the
/// close hub invokes it), but the stream is the supported API.
@Deprecated('listen to desktopApp.windowClosed instead')
void Function(String name)? get onWindowClosed => _platform.onWindowClosed;
@Deprecated('listen to desktopApp.windowClosed instead')
set onWindowClosed(void Function(String name)? handler) =>
    _platform.onWindowClosed = handler;

@Deprecated('use desktopApp.windowForHandle(handle)')
DesktopWindow getWindowForHandle(int handle) {
  return _platform.getWindowForHandle(handle);
}

@Deprecated('use desktopApp.displays()')
Future<List<Display>> getDisplays() => desktopApp.displays();

@Deprecated('use appWindow.showNativeAlert(...)')
Future<int> showNativeAlert({
  required String title,
  String? message,
  List<String> buttons = const ['OK'],
  NativeAlertStyle style = NativeAlertStyle.info,
}) =>
    appWindow.showNativeAlert(
      title: title,
      message: message,
      buttons: buttons,
      style: style,
    );

@Deprecated('use appWindow.showNativeConfirm(...)')
Future<bool> showNativeConfirm({
  required String title,
  String? message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  NativeAlertStyle style = NativeAlertStyle.warning,
}) =>
    appWindow.showNativeConfirm(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      style: style,
    );

@Deprecated('use appWindow.showNativeMenu(...)')
Future<String?> showNativeMenu(
  List<NativeMenuItem> items, {
  Offset? position,
}) =>
    appWindow.showNativeMenu(items, position: position);

@Deprecated('use desktopApp.terminate()')
void terminateApp() {
  desktopApp.terminate();
}
