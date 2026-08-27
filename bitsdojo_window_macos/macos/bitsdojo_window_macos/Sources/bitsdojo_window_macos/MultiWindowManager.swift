import Cocoa
import FlutterMacOS
#if canImport(bitsdojo_window_macos_objc)
import bitsdojo_window_macos_objc
#endif

/// Manages multiple windows in a Flutter macOS application.
/// This class handles window creation, tracking, and lifecycle management.
public class MultiWindowManager {
    // MARK: - Singleton
    
    public static let shared = MultiWindowManager()
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Window Tracking
    
    private var secondaryWindows: [BitsdojoWindow] = []
    private var namedWindows: [String: BitsdojoWindow] = [:]
    private weak var primaryWindow: NSWindow?
    private var closingWindowHandles: Set<Int> = []

    /// One entry per owned window created via openNewWindow's modality.
    /// Modal entries carry a blocker view and a key observer; modeless
    /// entries carry nil for both. Because every modal session owns its
    /// OWN blocker/observer, tearing one down never strips a sibling
    /// dialog's — the parent only becomes interactive again when its
    /// last modal session is gone.
    private struct OwnershipSession {
        let dialog: NSWindow
        let parent: NSWindow
        let blocker: NSView?
        let keyObserver: NSObjectProtocol?
    }
    private var ownershipSessions: [OwnershipSession] = []

    /// JSON result strings set by a dialog's `setWindowResult`, delivered in
    /// the windowClosed broadcast when the window actually closes. Keyed by
    /// object identity, not windowNumber: the tracking arrays retain the
    /// NSWindow through willClose, while windowNumber can go non-positive
    /// once the window loses its device during teardown. Every entry is
    /// removed in handleWindowClose (willClose fires for every real close),
    /// so identifier reuse by a future allocation cannot resurrect a value.
    private var pendingWindowResults: [ObjectIdentifier: String] = [:]
    
    // MARK: - Configuration
    
    /// If true, the app will terminate when the primary window closes.
    /// Default: true
    public var shouldTerminateOnPrimaryClose: Bool = true
    
    /// The window class to use when creating new windows.
    /// Default: BitsdojoWindow.self
    /// Set this to your custom window class (e.g., MainFlutterWindow.self) to ensure
    /// plugin registration and custom configuration are applied to all windows.
    public var windowClass: BitsdojoWindow.Type = BitsdojoWindow.self

    /// Registers plugins on a newly created secondary window's engine.
    /// Set this once from the runner, e.g.:
    ///   MultiWindowManager.shared.pluginRegistrant = { RegisterGeneratedPlugins(registry: $0) }
    /// It is invoked only when the window class itself did not already
    /// register plugins in its setupFlutter() override — without either,
    /// every plugin call on the new engine throws MissingPluginException
    /// and the engine is never shut down on close.
    ///
    /// Note: a setupFlutter() override that registers plugins must do so
    /// synchronously and include BitsdojoWindowPlugin (registering it is how
    /// the manager detects "already registered"); partial manual
    /// registration would be double-registered by this registrant.
    public var pluginRegistrant: ((FlutterPluginRegistry) -> Void)?
    
    // MARK: - Public API
    
    /// Registers a window as the primary window.
    /// This is typically called automatically by the plugin.
    public func registerPrimaryWindow(_ window: NSWindow) {
        self.primaryWindow = window
        
        // Auto-detect window class from primary window
        if let bdwWindow = window as? BitsdojoWindow {
            self.windowClass = type(of: bdwWindow)
        }
    }
    
    /// Auto-detects the primary window using multiple fallback strategies.
    public func autoDetectPrimaryWindow() {
        // One-shot: never retarget once a primary is known. Plugin
        // registration on SECONDARY engines re-arms the 0.5s delayed detect
        // (BitsdojoWindowPlugin.register), at which point the just-opened
        // secondary is NSApp.mainWindow — retargeting would make closing the
        // real primary no longer terminate the app. primaryWindow is weak,
        // so re-detection still happens if the primary actually went away.
        guard primaryWindow == nil else { return }

        // Strategy 1: Try to get mainFlutterWindow from FlutterAppDelegate
        if let appDelegate = NSApp.delegate as? FlutterAppDelegate,
           let window = appDelegate.value(forKey: "mainFlutterWindow") as? NSWindow {
            registerPrimaryWindow(window)
            return
        }

        // Strategy 2: Use NSApp.mainWindow (never a tracked secondary)
        if let window = NSApp.mainWindow, !isTrackedSecondaryWindow(window) {
            registerPrimaryWindow(window)
            return
        }

        // Strategy 3: Find first BitsdojoWindow that isn't a tracked secondary
        if let window = NSApp.windows.first(where: {
            $0 is BitsdojoWindow && !isTrackedSecondaryWindow($0)
        }) {
            registerPrimaryWindow(window)
            return
        }
    }

    private func isTrackedSecondaryWindow(_ window: NSWindow) -> Bool {
        guard let bdwWindow = window as? BitsdojoWindow else { return false }
        return secondaryWindows.contains(where: { $0 === bdwWindow })
    }
    
    /// Opens a new window with the specified parameters.
    /// - Parameters:
    ///   - name: Optional name for the window (allows reuse)
    ///   - arguments: Optional arguments to pass to the Flutter engine
    ///   - size: Optional window size
    ///   - position: Optional window position (Dart top-left coordinates)
    /// - Returns: The created or reused window
    public func openNewWindow(
        name: String?,
        arguments: [String: Any]?,
        argumentsJson: String? = nil,
        size: NSSize?,
        position: NSPoint?,
        modality: String? = nil,
        parent: NSWindow? = nil
    ) -> BitsdojoWindow {
        // Adopt the app's window subclass before creating anything. The
        // 0.5s-delayed auto-detect in BitsdojoWindowPlugin.register may not
        // have run yet if a window opens right after startup — without this,
        // early windows are created as plain BitsdojoWindow and miss the
        // subclass's plugin registration.
        if primaryWindow == nil {
            autoDetectPrimaryWindow()
        }

        // Check if window with this name already exists.
        // Modality is intentionally ignored on this path: reuse only
        // focuses a window whose ownership was fixed at creation time.
        if let name = name, let existingWindow = namedWindows[name] {
            if canReuseWindow(existingWindow) {
                existingWindow.windowArguments = arguments

                // Notify plugin that arguments changed
                if let plugin = BitsdojoWindowPlugin.getPluginForWindow(existingWindow) {
                    plugin.updateArguments(arguments)
                }

                if existingWindow.isMiniaturized {
                    existingWindow.deminiaturize(nil)
                }
                existingWindow.makeKeyAndOrderFront(nil as Any?)
                return existingWindow
            }

            namedWindows.removeValue(forKey: name)
        }
        
        // Calculate frame
        var rect = NSRect(x: 0, y: 0, width: 600, height: 450)
        if let size = size {
            rect.size = size
        }
        
        // Create new window using configured window class.
        //
        // `defer: true` delays the allocation of the window's backing
        // store until the first `orderFront` / `makeKeyAndOrderFront`.
        // This gives `configureWindow()` (called inside the BitsdojoWindow
        // `required init`) a chance to flip isOpaque → false and
        // backgroundColor → .clear BEFORE the backing store is created,
        // which means the very first frame the user sees has a clean
        // transparent backing — no "white flash" during the first
        // makeKeyAndOrderFront or on subsequent Space swipes that
        // re-allocate the backing store.
        //
        // Previously this was `defer: false`, which created the backing
        // store DURING `super.init` (before configureWindow could run),
        // baking a `windowBackgroundColor`-tinted first frame into
        // macOS's window cache.
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let newWindow = windowClass.init(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: true)
        newWindow.isReleasedWhenClosed = false
        
        // Ownership and depth must agree, so both derive from the same
        // resolved window: the calling engine's window when the plugin
        // passed one, else the key-window heuristic for native call sites
        // that predate the parameter.
        let effectiveParent: NSWindow? = parent ?? (NSApp.keyWindow as? BitsdojoWindow) ?? primaryWindow

        // Set position if provided (translate from Dart top-left to macOS bottom-left)
        if let position = position {
            let translatedPosition = translateDartPosition(position)
            let probe = NSRect(x: translatedPosition.x,
                               y: translatedPosition.y - rect.size.height,
                               width: rect.size.width, height: rect.size.height)
            if NSScreen.screens.contains(where: { $0.frame.intersects(probe) }) {
                newWindow.setFrameTopLeftPoint(translatedPosition)
            } else {
                // Saved on a monitor that is no longer attached: a window
                // restored off every screen cannot even be dragged back.
                newWindow.center()
            }
        } else if NSScreen.main != nil {
            newWindow.center()
        }
        
        // Configure window properties
        newWindow.windowName = name
        newWindow.windowArguments = arguments
        newWindow.windowArgumentsJson = argumentsJson
        
        // Set depth based on parent
        if let owner = effectiveParent as? BitsdojoWindow {
            newWindow.depth = owner.depth + 1
        }
        
        // Register with bitsdojo_window
        BitsdojoWindowPlugin.registerWindow(newWindow)

        // Setup Flutter engine
        newWindow.setupFlutter()

        // Ensure the new engine has plugins. A window subclass following the
        // documented pattern registers them inside its setupFlutter()
        // override (detected via valuePublished); a plain BitsdojoWindow
        // registers nothing, which would leave the engine plugin-less AND
        // leak it on close (teardown lives in BitsdojoWindowPlugin's
        // willClose observer).
        if let flutterViewController = newWindow.contentViewController as? FlutterViewController,
           flutterViewController.valuePublished(byPlugin: "BitsdojoWindowPlugin") == nil {
            if let registrant = pluginRegistrant {
                registrant(flutterViewController)
            } else {
                // Minimal fallback: register this plugin alone so window
                // control, windowReady delivery, and engine teardown work.
                BitsdojoWindowPlugin.register(
                    with: flutterViewController.registrar(forPlugin: "BitsdojoWindowPlugin"))
                NSLog("bitsdojo_window: new window engine had no plugins registered; " +
                      "only BitsdojoWindowPlugin was added as a fallback. Set " +
                      "MultiWindowManager.shared.pluginRegistrant = { RegisterGeneratedPlugins(registry: $0) } " +
                      "(or use a BitsdojoWindow subclass that registers plugins in setupFlutter()) " +
                      "so all plugins work in secondary windows.")
            }
        }
        
        // Track window
        secondaryWindows.append(newWindow)
        if let name = name {
            namedWindows[name] = newWindow
        }

        // Show window. Batch screen updates from setupFlutter() and any
        // subsequent property writes into a single composition flush —
        // without this the window briefly appears with a partial setup
        // state on screen before the next vsync, which on translucent
        // / fullsize-content windows surfaces as the same "white
        // flash" we fight elsewhere.
        newWindow.disableScreenUpdatesUntilFlush()
        newWindow.makeKeyAndOrderFront(nil as Any?)

        if let owner = effectiveParent, owner !== newWindow,
           modality == "modeless" || modality == "modal" {
            // AppKit child windows also move with their parent — an
            // accepted platform difference from Win32 owned windows.
            owner.addChildWindow(newWindow, ordered: .above)

            var blocker: NSView? = nil
            var keyObserver: NSObjectProtocol? = nil
            if modality == "modal", let ownerContent = owner.contentView {
                // Covers the content view only: a native-frame parent's
                // miniaturize/zoom buttons stay live during the modal.
                // Accepted — bitsdojo custom-frame apps draw their real
                // controls in Flutter content, which IS covered.
                let blockerView = ModalInputBlockerView(frame: ownerContent.bounds)
                blockerView.autoresizingMask = [.width, .height]
                blockerView.dialog = newWindow
                ownerContent.addSubview(blockerView, positioned: .above, relativeTo: nil)
                blocker = blockerView

                // The blocker only intercepts the mouse; keyboard focus
                // can still reach the parent without a click (Cmd-`,
                // Mission Control), so bounce key status to the dialog.
                keyObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: owner,
                    queue: .main
                ) { [weak newWindow] _ in
                    guard let dialog = newWindow else { return }
                    // makeKeyAndOrderFront does not deminiaturize — a
                    // dialog the user minimized would beep from the Dock
                    // forever (the named-reuse path knows the same trick).
                    if dialog.isMiniaturized {
                        dialog.deminiaturize(nil)
                    }
                    dialog.makeKeyAndOrderFront(nil)
                }
            }
            ownershipSessions.append(OwnershipSession(
                dialog: newWindow,
                parent: owner,
                blocker: blocker,
                keyObserver: keyObserver
            ))
        }

        return newWindow
    }
    
    /// Closes a window by name.
    public func closeWindow(named name: String) {
        if let window = namedWindows[name] {
            window.close()
        }
    }
    
    /// Gets a window by name.
    public func getWindow(named name: String) -> BitsdojoWindow? {
        return namedWindows[name]
    }

    /// Stores the result a dialog wants delivered with its windowClosed
    /// broadcast. Last write wins: a Dart onClose veto can cancel the close
    /// that followed closeWithResult, and a later closeWithResult must
    /// replace the abandoned value, not sit behind it.
    public func setWindowResult(window: NSWindow, json: String?) {
        let key = ObjectIdentifier(window)
        if let json = json {
            pendingWindowResults[key] = json
        } else {
            pendingWindowResults.removeValue(forKey: key)
        }
    }
    
    // MARK: - Internal Methods
    
    internal func handleWindowClose(_ window: NSWindow) {
        // The willClose observer fires for EVERY NSWindow in the process
        // (save panels, alerts, other plugins' windows) — only touch
        // closingWindowHandles for windows this manager tracks, otherwise
        // the set grows without bound over the app's lifetime.
        //
        // A vetoed close never gets here (markWindowClosing runs on the
        // REQUEST; willClose only fires on an actual close), so ownership
        // sessions survive a Dart veto untouched.

        // Read-and-clear this window's dialog result up front, before any
        // teardown below. Clearing here — on EVERY real close, broadcast or
        // not — is what keeps a window reopened under the same name from
        // delivering a stale result; the local carries the value to the
        // broadcast further down. The parent-teardown path closes orphaned
        // dialogs reentrantly, and each of those reentrant willClose calls
        // removes its own key, so results are never cross-cleared.
        // (removeValue on the untracked windows this observer also sees is
        // a no-op — the dictionary only ever holds setWindowResult callers.)
        let pendingResult = pendingWindowResults.removeValue(forKey: ObjectIdentifier(window))

        // Owned-window sessions come first: a dialog is also a tracked
        // secondary window, so its session must be torn down before the
        // early return below.
        if ownershipSessions.contains(where: { $0.dialog === window }) {
            // Only hand focus back when the closing dialog actually held
            // it — a modeless dialog closed programmatically (e.g.
            // closeWindow(named:) from another engine) while the user
            // works elsewhere must not yank its parent to front. Win32
            // owner activation follows the same rule.
            let dialogWasKey = NSApp.keyWindow === window
            var reKeyParent: NSWindow? = nil
            for session in ownershipSessions where session.dialog === window {
                if let observer = session.keyObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                session.blocker?.removeFromSuperview()
                if session.parent.childWindows?.contains(window) == true {
                    session.parent.removeChildWindow(window)
                }
                reKeyParent = session.parent
            }
            ownershipSessions.removeAll(where: { $0.dialog === window })
            // Any sibling modal session keeps its own blocker/observer,
            // so the parent stays blocked until the LAST one closes; the
            // re-key below then just triggers the sibling's key observer,
            // which bounces focus to the remaining dialog.
            if dialogWasKey {
                reKeyParent?.makeKeyAndOrderFront(nil)
            }
        }

        if ownershipSessions.contains(where: { $0.parent === window }) {
            let orphaned = ownershipSessions.filter { $0.parent === window }
            ownershipSessions.removeAll(where: { $0.parent === window })
            for session in orphaned {
                if let observer = session.keyObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                session.blocker?.removeFromSuperview()
                // Win32 destroys owned windows together with their owner;
                // close them here so the two platforms agree. Sessions are
                // dropped BEFORE closing so the reentrant willClose for
                // each dialog doesn't try to re-key the vanishing parent.
                session.dialog.close()
            }
        }

        // Check if it's a secondary window
        if let bdwWindow = window as? BitsdojoWindow,
           secondaryWindows.contains(where: { $0 === bdwWindow }) {
            // Remove from tracking. Only drop the namedWindows entry if it
            // still points at THIS window — a replacement window may have
            // been created under the same name while this one was closing.
            secondaryWindows.removeAll(where: { $0 === bdwWindow })
            if let name = bdwWindow.windowName, namedWindows[name] === bdwWindow {
                namedWindows.removeValue(forKey: name)
                // Tell every REMAINING window. Only when this window was
                // still the name's current holder: a replacement window
                // already created under the same name means the name is not
                // actually gone from the user's point of view.
                broadcastWindowClosed(name, result: pendingResult)
            }
            closingWindowHandles.remove(window.windowNumber)
            return
        }

        // Check if it's the primary window
        if window === primaryWindow {
            if shouldTerminateOnPrimaryClose {
                // Post notification for AppDelegate to handle termination
                NotificationCenter.default.post(
                    name: NSNotification.Name("BitsdojoWindowPrimaryWillClose"),
                    object: nil
                )
            }
            closingWindowHandles.remove(window.windowNumber)
        }
    }

    internal func markWindowClosing(_ window: NSWindow) {
        closingWindowHandles.insert(window.windowNumber)
    }

    /// Notifies every remaining window's Dart engine that [name] closed,
    /// carrying the JSON result the window stored via setWindowResult (nil
    /// when it never set one — a plain close). The closing window's own
    /// engine is being torn down and is not told.
    private func broadcastWindowClosed(_ name: String, result: String?) {
        var targets: [NSWindow] = []
        if let primary = primaryWindow {
            targets.append(primary)
        }
        targets.append(contentsOf: secondaryWindows)
        for target in targets {
            BitsdojoWindowPlugin.getPluginForWindow(target)?.notifyWindowClosed(name, result: result)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        // Observe all window close notifications
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.handleWindowClose(window)
        }
    }
    
    private func canReuseWindow(_ window: BitsdojoWindow) -> Bool {
        if closingWindowHandles.contains(window.windowNumber) {
            // markWindowClosing runs when a close is REQUESTED (before Dart's
            // onClose interceptor decides). A vetoed close never fires
            // willClose — and Dart sends no veto notification — so the mark
            // would otherwise poison reuse of this named window forever.
            // A window that is still on screen demonstrably survived the
            // request; clear the stale mark. Known limitation: a close still
            // being deliberated also passes this check — reusing (focus +
            // args update) is benign there, and if the user then confirms
            // the close the window simply closes as requested.
            if window.isVisible || window.isMiniaturized {
                closingWindowHandles.remove(window.windowNumber)
            } else {
                return false
            }
        }
        if window.screen == nil {
            return false
        }
        return window.isVisible || window.isMiniaturized
    }

    /// Dart-side window coordinates are GLOBAL desktop coordinates (primary
    /// screen's top-left is (0,0), y down). Always translate against the
    /// PRIMARY screen; per-target-screen translation re-based saved
    /// positions onto whatever screen the manager guessed.
    private func translateDartPosition(_ position: NSPoint) -> NSPoint {
        guard let primary = NSScreen.screens.first else { return position }
        let topY = primary.frame.origin.y + primary.frame.size.height - position.y
        return NSPoint(x: position.x, y: topY)
    }
}

/// Transparent overlay that keeps a modal dialog's parent from taking
/// mouse input. It only covers the mouse — key status reaching the parent
/// is handled by the didBecomeKey observer in MultiWindowManager, because
/// a view cannot intercept window-level focus changes.
private final class ModalInputBlockerView: NSView {
    weak var dialog: NSWindow?

    override func mouseDown(with event: NSEvent) {
        // The native cue for clicking a blocked window: beep and put the
        // dialog back in front — out of the Dock first if the user
        // minimized it, since makeKeyAndOrderFront alone won't.
        NSSound.beep()
        guard let dialog = dialog else { return }
        if dialog.isMiniaturized {
            dialog.deminiaturize(nil)
        }
        dialog.makeKeyAndOrderFront(nil)
    }
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}
