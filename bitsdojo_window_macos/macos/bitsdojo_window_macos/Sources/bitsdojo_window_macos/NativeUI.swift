import Cocoa
import FlutterMacOS

/// System alerts and popup menus, owned by one window.
///
/// Every entry point takes the window (or view) of the *calling* engine, so in
/// a multi-window app the sheet hangs off the window that asked for it and the
/// menu pops up in that window's view.
enum NativeUI {
  static func showAlert(
    window: NSWindow?,
    args: [String: Any],
    result: @escaping FlutterResult
  ) {
    let alert = NSAlert()
    alert.messageText = args["title"] as? String ?? ""
    if let message = args["message"] as? String, !message.isEmpty {
      alert.informativeText = message
    }
    switch args["style"] as? Int ?? 0 {
    case 1: alert.alertStyle = .warning
    case 2: alert.alertStyle = .critical
    default: alert.alertStyle = .informational
    }

    let buttons = args["buttons"] as? [String] ?? []
    for title in (buttons.isEmpty ? ["OK"] : buttons) {
      alert.addButton(withTitle: title)
    }

    // NSAlert numbers its buttons from `alertFirstButtonReturn` in the order
    // they were added, which is the order Dart listed them.
    func index(of response: NSApplication.ModalResponse) -> Int {
      return response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    if let window = window, window.isVisible {
      alert.beginSheetModal(for: window) { response in
        result(index(of: response))
      }
    } else {
      // Nothing to hang a sheet on — the window is still hidden (hide-on-startup)
      // or this engine has none. A free-floating app-modal alert is what's left.
      result(index(of: alert.runModal()))
    }
  }

  static func showMenu(
    view: NSView?,
    args: [String: Any],
    result: @escaping FlutterResult
  ) {
    let items = args["items"] as? [[String: Any]] ?? []
    if items.isEmpty {
      result(nil)
      return
    }

    let pick = MenuPick()
    let menu = buildMenu(items, pick: pick)

    // `popUp` is synchronous: it spins its own run loop and returns once the
    // menu closes, by which point `pick.id` holds the selection.
    if let view = view,
       let x = args["x"] as? Double,
       let y = args["y"] as? Double {
      // Dart hands over logical pixels from the window's top-left; an unflipped
      // NSView measures from the bottom-left.
      let point = NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y)
      menu.popUp(positioning: nil, at: point, in: view)
    } else {
      // With no view, `at` is read in screen coordinates.
      menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    result(pick.id)
  }

  /// Holds the picked id for the lifetime of one popup. NSMenuItem needs a
  /// target object; a closure won't do.
  private final class MenuPick: NSObject {
    var id: String?

    @objc func pick(_ sender: NSMenuItem) {
      id = sender.representedObject as? String
    }
  }

  private static func buildMenu(_ items: [[String: Any]], pick: MenuPick) -> NSMenu {
    let menu = NSMenu()
    // Otherwise NSMenu decides for itself which items are enabled and
    // overrides the `enabled: false` the caller asked for.
    menu.autoenablesItems = false

    for item in items {
      guard let id = item["id"] as? String else {
        menu.addItem(.separator())
        continue
      }
      let menuItem = NSMenuItem(
        title: item["label"] as? String ?? "",
        action: #selector(MenuPick.pick(_:)),
        keyEquivalent: ""
      )
      menuItem.target = pick
      menuItem.representedObject = id
      menuItem.isEnabled = item["enabled"] as? Bool ?? true
      menuItem.state = (item["checked"] as? Bool ?? false) ? .on : .off

      if let submenu = item["submenu"] as? [[String: Any]] {
        // An item that opens a submenu is never picked itself.
        menuItem.action = nil
        menuItem.target = nil
        menuItem.submenu = buildMenu(submenu, pick: pick)
      }
      menu.addItem(menuItem)
    }
    return menu
  }
}
