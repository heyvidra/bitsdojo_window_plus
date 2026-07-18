library bitsdojo_window_macos;

import './window.dart';
import './native_api.dart';

class MacAppWindow extends MacOSWindow {
  MacAppWindow._() {
    super.handle = getAppWindow();
    if (handle == null) {
      throw StateError(
          'bitsdojo_window: could not get Flutter window handle. '
          'Ensure bitsdojo_window is initialized in your macOS runner (AppDelegate).');
    }
  }

  static final MacAppWindow _instance = MacAppWindow._();

  factory MacAppWindow() {
    return _instance;
  }
}
