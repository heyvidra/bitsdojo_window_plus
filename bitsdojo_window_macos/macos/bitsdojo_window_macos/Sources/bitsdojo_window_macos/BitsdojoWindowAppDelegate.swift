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

    // FlutterAppDelegate declares NSApplicationDelegate conformance, which is
    // why Swift accepts `super.applicationDidFinishLaunching` at all — but the
    // method is OPTIONAL in that protocol and FlutterAppDelegate does not
    // implement it (`nm` finds no such symbol in FlutterMacOS). The super call
    // therefore lands in message forwarding and throws
    // `doesNotRecognizeSelector:`.
    //
    // That exception has always been thrown; macOS's main run loop logs
    // uncaught ObjC exceptions and carries on, so nothing ever surfaced. An
    // app that installs a crash handler — Sentry's, in Vidra 1.12.1 — turns
    // the same exception into a terminated process on the first launch after
    // install, which is where the Apple Event that posts this notification
    // arrives.
    //
    // Asking first rather than deleting the call: if Flutter ever implements
    // it, skipping it silently would be its own bug.
    if FlutterAppDelegate.instancesRespond(
      to: #selector(NSApplicationDelegate.applicationDidFinishLaunching(_:))
    ) {
      super.applicationDidFinishLaunching(notification)
    }
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
