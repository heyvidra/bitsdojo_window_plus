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
        position: NSPoint?
    ) -> BitsdojoWindow {
        // Adopt the app's window subclass before creating anything. The
        // 0.5s-delayed auto-detect in BitsdojoWindowPlugin.register may not
        // have run yet if a window opens right after startup — without this,
        // early windows are created as plain BitsdojoWindow and miss the
        // subclass's plugin registration.
        if primaryWindow == nil {
            autoDetectPrimaryWindow()
        }

        // Check if window with this name already exists
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
        
        // Set position if provided (translate from Dart top-left to macOS bottom-left)
        let parent = (NSApp.keyWindow as? BitsdojoWindow) ?? (primaryWindow as? BitsdojoWindow)

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
        if let parent = parent {
            newWindow.depth = parent.depth + 1
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
    
    // MARK: - Internal Methods
    
    internal func handleWindowClose(_ window: NSWindow) {
        // The willClose observer fires for EVERY NSWindow in the process
        // (save panels, alerts, other plugins' windows) — only touch
        // closingWindowHandles for windows this manager tracks, otherwise
        // the set grows without bound over the app's lifetime.

        // Check if it's a secondary window
        if let bdwWindow = window as? BitsdojoWindow,
           secondaryWindows.contains(where: { $0 === bdwWindow }) {
            // Remove from tracking. Only drop the namedWindows entry if it
            // still points at THIS window — a replacement window may have
            // been created under the same name while this one was closing.
            secondaryWindows.removeAll(where: { $0 === bdwWindow })
            if let name = bdwWindow.windowName, namedWindows[name] === bdwWindow {
                namedWindows.removeValue(forKey: name)
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
