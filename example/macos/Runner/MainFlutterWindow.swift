import Cocoa
import FlutterMacOS

import bitsdojo_window_macos

class MainFlutterWindow: BitsdojoWindow {
  override func bitsdojo_window_configure() -> UInt {
    return BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP
  }
  
  override func bitsdojo_window_title_bar_height() -> Double {
    return 50.0
  }
  
  override func setupFlutter() {
    super.setupFlutter()

    // Register plugins for this window's Flutter engine
    if let flutterViewController = self.contentViewController as? FlutterViewController {
      RegisterGeneratedPlugins(registry: flutterViewController)
    }

    // Safety net: if a future window is created with a class that doesn't
    // register plugins itself, MultiWindowManager uses this to register them.
    MultiWindowManager.shared.pluginRegistrant = { registry in
      RegisterGeneratedPlugins(registry: registry)
    }
  }
}

