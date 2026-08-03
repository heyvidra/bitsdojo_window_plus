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
        // Strategy 1: Try to get mainFlutterWindow from FlutterAppDelegate
        if let appDelegate = NSApp.delegate as? FlutterAppDelegate,
           let window = appDelegate.value(forKey: "mainFlutterWindow") as? NSWindow {
            registerPrimaryWindow(window)
            return
        }
        
        // Strategy 2: Use NSApp.mainWindow
        if let window = NSApp.mainWindow {
            registerPrimaryWindow(window)
            return
        }
        
        // Strategy 3: Find first BitsdojoWindow
        if let window = NSApp.windows.first(where: { $0 is BitsdojoWindow }) {
            registerPrimaryWindow(window)
            return
        }
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
            let targetScreen = parent?.screen ?? primaryWindow?.screen
            let translatedPosition = translateDartPosition(position, on: targetScreen)
            newWindow.setFrameTopLeftPoint(translatedPosition)
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
        closingWindowHandles.insert(window.windowNumber)
        
        // Check if it's a secondary window
        if let bdwWindow = window as? BitsdojoWindow,
           secondaryWindows.contains(where: { $0 === bdwWindow }) {
            // Remove from tracking
            secondaryWindows.removeAll(where: { $0 === bdwWindow })
            if let name = bdwWindow.windowName {
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
            return false
        }
        if window.screen == nil {
            return false
        }
        return window.isVisible || window.isMiniaturized
    }

    private func translateDartPosition(_ position: NSPoint, on screen: NSScreen?) -> NSPoint {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return position
        }
        let visibleFrame = screen.visibleFrame
        let topY = visibleFrame.origin.y + visibleFrame.size.height - position.y
        return NSPoint(x: position.x, y: topY)
    }
}
