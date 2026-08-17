import 'dart:ui';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_bitsdojo_window.dart';
import './display.dart';
import './native_ui.dart';
import './window.dart';

export './display.dart';
export './native_ui.dart';
export './window.dart';
export './window_event.dart';
export './window_common.dart';
export './window_not_implemented.dart';
export './platform_not_implemented.dart';

/// The interface that implementations of bitsdojo_window must implement.
///
/// Platform implementations should extend this class rather than implement it as `bitsdojo_window`
/// does not consider newly added methods to be breaking changes. Extending this class
/// (using `extends`) ensures that the subclass will get the default implementation, while
/// platform implementations that `implements` this interface will be broken by newly added
/// [BitsdojoWindowPlatform] methods.
abstract class BitsdojoWindowPlatform extends PlatformInterface {
  /// Constructs a BitsdojoWindowPlatform.
  BitsdojoWindowPlatform() : super(token: _token);

  static final Object _token = Object();

  static BitsdojoWindowPlatform _channelInstance =
      MethodChannelBitsdojoWindow();
  static BitsdojoWindowPlatform _instance = _channelInstance;

  /// The default instance of [BitsdojoWindowPlatform] to use.
  ///
  /// Defaults to [MethodChannelBitsdojoWindow].
  static BitsdojoWindowPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [BitsdojoWindowPlatform] when they register themselves.
  static set instance(BitsdojoWindowPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  void doWhenWindowReady(VoidCallback callback) {
    throw UnimplementedError('doWhenWindowReady() has not been implemented.');
  }

  DesktopWindow get appWindow {
    throw UnimplementedError('appWindow has not been implemented.');
  }

  void dragAppWindow() async {
    _channelInstance.dragAppWindow();
  }

  DesktopWindow getWindowForHandle(int handle) {
    throw UnimplementedError('getWindowForHandle() has not been implemented.');
  }

  bool isMainWindow(int handle) {
    return true; // Default to true for single-handle platforms
  }

  /// Seeds this engine's window identity from values known at engine startup
  /// (e.g. parsed from dart entrypoint arguments), so `window.name` /
  /// `window.arguments` are correct before the native `windowReady` message
  /// arrives. Platforms without startup identity ignore this.
  void seedWindowIdentity({
    String? name,
    Map<String, dynamic>? arguments,
    bool? isMainWindow,
  }) {}

  void terminateApp() {
    // Default to nothing or common exit
  }

  Future<void> openNewWindow({
    String? name,
    Size? size,
    Offset? position,
    Map<String, dynamic>? arguments,
  }) {
    throw UnimplementedError('openNewWindow() has not been implemented.');
  }

  /// Whether a window opened under [name] currently exists.
  ///
  /// Defaults to false rather than throwing: callers use this to decide
  /// whether to act on a window, and "no such window" is the correct answer
  /// on platforms without multi-window support.
  Future<bool> hasWindow(String name) async => false;

  /// Closes the window opened under [name], if it exists. A no-op when it
  /// does not — closing an absent window needs no error.
  Future<void> closeWindow(String name) async {}

  /// Called in this engine when a named window elsewhere in the process
  /// closes — however it closed: [closeWindow], its own close button, or
  /// `appWindow.close()` from its own Dart. The window's own engine is gone
  /// by then, so it never receives this callback about itself.
  void Function(String name)? onWindowClosed;

  /// Shows an OS-native alert owned by the window this engine draws into: a
  /// sheet on macOS, a window-modal dialog on Windows and Linux. Returns the
  /// index of the pressed button in [buttons], or -1 when the alert was
  /// dismissed without pressing one (Esc / close box, where the platform
  /// allows it).
  ///
  /// [buttons] is affirmative-first — `['Delete', 'Cancel']` — matching where
  /// each platform puts its default button. Windows picks a system button set
  /// from the button *count* and ignores the labels; see the note in
  /// `native_ui.cpp`.
  ///
  /// Both native-UI calls route through the engine's own channel rather than a
  /// window handle: the plugin instance already knows which window it belongs
  /// to, which is what makes them land on the right window in a multi-window
  /// app.
  Future<int> showNativeAlert({
    required String title,
    String? message,
    List<String> buttons = const ['OK'],
    NativeAlertStyle style = NativeAlertStyle.info,
  }) {
    return _channelInstance.showNativeAlert(
      title: title,
      message: message,
      buttons: buttons,
      style: style,
    );
  }

  /// Pops up an OS-native menu over this engine's window and completes when it
  /// closes, with the [NativeMenuItem.id] of the picked entry — or null when
  /// the menu was dismissed.
  ///
  /// [position] is in logical pixels from the window's top-left, so Flutter's
  /// `details.globalPosition` can be passed straight through. Null pops the
  /// menu at the mouse pointer.
  Future<String?> showNativeMenu(
    List<NativeMenuItem> items, {
    Offset? position,
  }) {
    return _channelInstance.showNativeMenu(items, position: position);
  }

  /// The monitors attached to the machine, in no guaranteed order.
  ///
  /// Empty on a platform that can't enumerate them: code placing a window on a
  /// chosen display needs a fallback for "only one screen" anyway, so an empty
  /// list is the useful answer and an exception would force every call site to
  /// catch. Coordinates share `DesktopWindow.position`'s space.
  Future<List<Display>> getDisplays() {
    return _channelInstance.getDisplays();
  }

  void setAlwaysOnTop(bool onTop) {
    throw UnimplementedError('setAlwaysOnTop() has not been implemented.');
  }

  void setBackgroundEffect(WindowEffect effect) {
    throw UnimplementedError('setBackgroundEffect() has not been implemented.');
  }

  void setWindowTitleBarButtonVisibility(
      DesktopWindowButton button, bool visible) {
    throw UnimplementedError(
        'setWindowTitleBarButtonVisibility() has not been implemented.');
  }
}
