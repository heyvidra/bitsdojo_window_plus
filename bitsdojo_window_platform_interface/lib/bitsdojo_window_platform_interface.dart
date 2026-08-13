import 'dart:ui';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_bitsdojo_window.dart';
import './window.dart';

export './window.dart';
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
