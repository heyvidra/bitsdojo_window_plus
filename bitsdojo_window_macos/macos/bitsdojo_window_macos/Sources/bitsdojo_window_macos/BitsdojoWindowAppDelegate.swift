import Cocoa
import FlutterMacOS

open class BitsdojoWindowAppDelegate: FlutterAppDelegate {
  private var isExiting = false

  open override func applicationDidFinishLaunching(
    _ notification: Notification
  ) {
    NotificationCenter.default.addObserver(
      forName: NSNotification.Name("BitsdojoWindowPrimaryWillClose"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.isExiting = true
      NSApp.terminate(self)
    }

    signal(SIGPIPE, SIG_IGN)
    super.applicationDidFinishLaunching(notification)
  }

  open override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    if isExiting {
      return .terminateNow
    }
    if let window = mainFlutterWindow {
      BitsdojoWindowPlugin.closeRequested(window)
      return .terminateCancel
    }
    return .terminateNow
  }

  open override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    return false
  }

  open override func applicationSupportsSecureRestorableState(
    _ app: NSApplication
  ) -> Bool {
    return true
  }
}
