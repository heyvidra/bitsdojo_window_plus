import Cocoa
import bitsdojo_window_macos

@main
class AppDelegate: BitsdojoWindowAppDelegate {
    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
  return true
}
}
