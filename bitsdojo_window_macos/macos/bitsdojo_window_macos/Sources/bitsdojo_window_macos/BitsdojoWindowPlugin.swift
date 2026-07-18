import Cocoa
import FlutterMacOS
#if canImport(bitsdojo_window_macos_objc)
import bitsdojo_window_macos_objc
#endif

@objc(BitsdojoWindowPlugin)
public class BitsdojoWindowPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?
  private static var instances = NSMapTable<NSWindow, BitsdojoWindowPlugin>(keyOptions: .weakMemory, valueOptions: .strongMemory)
  private static var globalObserverTokens: [NSObjectProtocol] = []
  private var lifecycleObserverTokens: [NSObjectProtocol] = []

  init(channel: FlutterMethodChannel, registrar: FlutterPluginRegistrar) {
    self.channel = channel
    self.registrar = registrar
    super.init()
  }

  deinit {
    removeLifecycleObservers()
  }

  public static func getPluginForWindow(_ window: NSWindow) -> BitsdojoWindowPlugin? {
    return instances.object(forKey: window)
  }

  public static func unregisterWindow(_ window: NSWindow) {
    if let plugin = instances.object(forKey: window) {
      plugin.removeLifecycleObservers()
      instances.removeObject(forKey: window)
    }
  }

  public static func registerWindow(_ window: NSWindow) {
    let bdwAPI = bitsdojo_window_api().pointee
    bdwAPI.privateAPI.pointee.setAppWindow(window)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "bitsdojo/window", binaryMessenger: registrar.messenger)
    let instance = BitsdojoWindowPlugin(channel: channel, registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)

    instance.associateAndTrySendReady()
    
    // Auto-detect and register primary window
    // 🔧 Add delay to ensure Flutter engine is fully initialized on first launch
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      BitsdojoWindowPlugin.isReady = true
      MultiWindowManager.shared.autoDetectPrimaryWindow()
    }
  }
  
  // 🔧 Safety flag to prevent early lifecycle events
  private static var isReady = false

  // Cap on `associateAndTrySendReady` retries. The default 10ms
  // back-off × 200 attempts = 2 s total — generous enough for the
  // slowest cold-start cases (heavy multi-window apps, debug builds
  // on first launch) without spinning forever if the engine never
  // produces a window (e.g. headless test runs, plugin loaded into a
  // process that never opens an NSWindow).
  private static let kMaxAssociateRetries = 200
  private var associateRetryCount = 0

  private func associateAndTrySendReady() {
    guard let registrar = self.registrar else { return }
    // Try to find the window associated with this engine
    if let window = registrar.viewController?.view.window ?? NSApp.windows.first(where: { $0.contentViewController == registrar.viewController }) {
        BitsdojoWindowPlugin.instances.setObject(self, forKey: window)

        // 🔧 Ensure window is registered with the native API
        BitsdojoWindowPlugin.registerWindow(window)

        self.startLifecycleMonitoring(window: window)

        // Send ready in next run loop to ensure engine is ready for messages
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self = self, let window = window else { return }

            let handle = Int(bitPattern: Unmanaged.passUnretained(window).toOpaque())
            let bdwAPI = bitsdojo_window_api().pointee;
            let isPrimary = bdwAPI.publicAPI.pointee.isPrimaryWindow(window);

            let bdwWindow = window as? BitsdojoWindow
            let depth = bdwWindow?.depth ?? 0
            let name = bdwWindow?.windowName
            let arguments = bdwWindow?.windowArguments

            self.channel.invokeMethod("windowReady", arguments: [
                "handle": handle,
                "isPrimary": isPrimary,
                "depth": depth,
                "name": name as Any,
                "arguments": arguments as Any
            ])
        }
    } else {
        // Window not ready yet, try again with a SMALL delay to prevent
        // high-frequency recursion that could hang the UI thread in
        // merged engine mode. Bounded by `kMaxAssociateRetries` so we
        // don't spin forever in plugin-loaded-without-window cases.
        associateRetryCount += 1
        if associateRetryCount >= BitsdojoWindowPlugin.kMaxAssociateRetries {
            NSLog("[Bitsdojo] associateAndTrySendReady: giving up after %d retries (window never appeared)",
                  associateRetryCount)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            self?.associateAndTrySendReady()
        }
    }
  }

  // 🔧 Native Lifecycle Management
  // Tracks global visibility and app activation to drive AppLifecycleState.
  
  private static var visibleWindowCount = 0
  private static var isAppActive: Bool = false
  private static var lastSentState: String? = nil
  private static var globalObserversRegistered = false
  private static var lifecycleDebounceWorkItem: DispatchWorkItem?

  private func startLifecycleMonitoring(window: NSWindow) {
      removeLifecycleObservers()

      // Enable mouse events even in background (fixes hover issue natively)
      window.acceptsMouseMovedEvents = true
      
      // 1. Register Global Observers (Once)
      if !BitsdojoWindowPlugin.globalObserversRegistered {
          let didBecomeActiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: nil) { _ in
              BitsdojoWindowPlugin.isAppActive = true
              BitsdojoWindowPlugin.recalculateLifecycle()
          }
          let didResignActiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: nil) { _ in
              BitsdojoWindowPlugin.isAppActive = false
              BitsdojoWindowPlugin.recalculateLifecycle()
          }
          BitsdojoWindowPlugin.globalObserverTokens = [
            didBecomeActiveObserver,
            didResignActiveObserver,
          ]
           // Initialize app active state
          BitsdojoWindowPlugin.isAppActive = NSApp.isActive
          BitsdojoWindowPlugin.globalObserversRegistered = true
      }

      // 2. Monitor Window Occlusion
      let occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: nil) { _ in
          BitsdojoWindowPlugin.recalculateLifecycle()
      }
      
      // 3. Monitor Closing
      let closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { [weak self] _ in
          // Deterministically tear down this window's Flutter engine.
          // Without this, the engine's native handle dies whenever the view
          // controller happens to detach, while the ObjC FlutterEngine object
          // stays alive in retain chains — and every later message to its
          // messenger logs "'FlutterEngineSendPlatformMessage' returned
          // 'kInvalidArguments'. Invalid engine handle."
          //
          // Grab the view controller from both possible owners: the window
          // (if the ObjC controller's windowWillClose hasn't detached it yet
          // — observer order on the same notification is undefined) or the
          // plugin registrar.
          let flutterVC = (window.contentViewController as? FlutterViewController)
              ?? (self?.registrar?.viewController as? FlutterViewController)
          BitsdojoWindowPlugin.unregisterWindow(window)

          // Never shut down the primary window's engine here: closing the
          // primary window terminates the app through its own path.
          let bdwAPI = bitsdojo_window_api().pointee
          let isPrimary = bdwAPI.publicAPI.pointee.isPrimaryWindow(window)
          if !isPrimary, let flutterVC = flutterVC {
              window.contentViewController = nil
              let engine = flutterVC.engine
              engine.shutDownEngine()
              // The FlutterEngine object can outlive shutDownEngine():
              // notification-center registrations whose blocks capture the
              // engine keep it alive (verified with `leaks --trace`: the
              // only remaining owner of closed windows' engines is
              // CFXNotificationRegistrar). The zombie engine then keeps
              // receiving app-activation notifications and logs
              // "'FlutterEngineSendPlatformMessage' returned
              // 'kInvalidArguments'" on every focus change. Detach it from
              // the notification centers so it goes silent.
              NotificationCenter.default.removeObserver(engine)
              NotificationCenter.default.removeObserver(flutterVC)
              NSWorkspace.shared.notificationCenter.removeObserver(engine)
              // FlutterAppDelegate broadcasts app-activation events to every
              // engine registered in its (weak) lifecycle registrar. The
              // registrar doesn't retain the engine, but it DOES keep
              // delivering to it as long as the object is alive — and system
              // blocks (Metal/audio) can keep a shut-down engine alive for a
              // while. Deregister explicitly so the dead engine stops
              // receiving flutter/lifecycle sends.
              if let provider = NSApp.delegate as? FlutterAppLifecycleProvider,
                 let delegate = engine as? NSObject & FlutterAppLifecycleDelegate {
                  provider.removeApplicationLifecycleDelegate(delegate)
              }
          }

          // Delay check to let window close
          DispatchQueue.main.async {
              BitsdojoWindowPlugin.recalculateLifecycle()
          }
          self?.removeLifecycleObservers()
      }
      lifecycleObserverTokens = [occlusionObserver, closeObserver]
      
      // Initial State Check
      BitsdojoWindowPlugin.recalculateLifecycle()
  }

  private func removeLifecycleObservers() {
      for token in lifecycleObserverTokens {
          NotificationCenter.default.removeObserver(token)
      }
      lifecycleObserverTokens.removeAll()
  }

  // Debounced entry point. Occlusion notifications fire for many TRANSIENT
  // reasons — a window moving, another window briefly passing over it, PiP
  // frame animation, Mission Control, or the window's own repaint — and
  // translating each into an AppLifecycleState send would pause/resume the
  // window's Flutter engine repeatedly (the "window keeps refreshing state":
  // overlays lose their anchor and jump, transient UI resets). Coalesce a
  // burst into a single SETTLED evaluation so only a real, stable transition
  // (genuine app background/foreground) reaches Flutter. A real transition is
  // delayed by at most the debounce interval, which is imperceptible.
  private static func recalculateLifecycle() {
      lifecycleDebounceWorkItem?.cancel()
      let work = DispatchWorkItem { performLifecycleRecalculation() }
      lifecycleDebounceWorkItem = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
  }

  private static func performLifecycleRecalculation() {
      var newVisibleCount = 0
      
      // Count windows that are actually on-screen and not minimized.
      //
      // Do NOT use occlusionState here: a window merely COVERED by another
      // window reports occlusionState WITHOUT .visible — and that happens
      // constantly in a multi-window app (the player window behind the main
      // window, another app's window passing over, PiP frame animation,
      // Mission Control). Driving the count off occlusion made those transient
      // coverings flip the aggregate app-lifecycle to inactive/hidden and back,
      // which the Flutter side reacts to by hiding/resetting UI (controls
      // vanish, an open menu overlay loses its anchor and jumps to the corner,
      // playback state churns) — "the window keeps refreshing state".
      //
      // -[NSWindow isVisible] stays true for a covered-but-on-screen window;
      // only a genuine minimize / orderOut / close changes isVisible /
      // isMiniaturized. That is the correct signal for app lifecycle.
      let keys = instances.keyEnumerator()
      while let window = keys.nextObject() as? NSWindow {
          if window.isVisible && !window.isMiniaturized {
              newVisibleCount += 1
          }
      }
      visibleWindowCount = newVisibleCount
      
      // Determine Target State
      // 1. If NO windows are visible -> Hidden
      // 2. If windows visible, but App NOT Active -> Inactive
      // 3. If windows visible AND App Active -> Resumed
      //
      // NOTE: keep emitting inactive/resumed on app-active changes. Under the
      // experimental merged UI+platform thread mode this app runs in, these
      // lifecycle sends double as the engine's frame/input kick — dropping
      // them (always-resumed) leaves a background window's engine dormant, so
      // clicks stop registering and the UI freezes. The click-activates ->
      // resumed -> focus-refresh clobber is addressed on the Flutter side
      // instead (see WindowEventManager handling).
      var newState = "AppLifecycleState.hidden"

      if visibleWindowCount > 0 {
          if isAppActive {
              newState = "AppLifecycleState.resumed"
          } else {
              newState = "AppLifecycleState.inactive"
          }
      }
      
      // Dedup: Only send if changed
      if newState != lastSentState {
          sendLifecycleEvent(newState)
          lastSentState = newState
      }
  }
  
  private static func sendLifecycleEvent(_ event: String) {
      // Gate lifecycle events until initialization is complete
      guard BitsdojoWindowPlugin.isReady else { return }

      // Iterate (window, plugin) pairs. keyEnumerator only vends live keys,
      // so entries whose weak window key was already zeroed are skipped.
      let keys = instances.keyEnumerator()
      while let window = keys.nextObject() as? NSWindow {
          guard let plugin = instances.object(forKey: window) else { continue }

          // Send asynchronously to avoid blocking the UI thread during
          // high-frequency events and to prevent deadlocks in merged engine
          // mode. ALL liveness checks happen INSIDE the closure — at send
          // time, not enqueue time — because the window can close (and its
          // engine shut down) between this loop and the async hop, which
          // used to log "'FlutterEngineSendPlatformMessage' returned
          // 'kInvalidArguments'. Invalid engine handle."
          DispatchQueue.main.async { [weak window, weak plugin] in
              guard let window = window,
                    let plugin = plugin,
                    // Window still registered with this exact plugin
                    instances.object(forKey: window) === plugin,
                    let registrar = plugin.registrar,
                    let viewController = registrar.viewController,
                    // Engine still attached to this window (not torn down)
                    viewController.view.window === window
              else { return }

              let lifecycleChannel = FlutterBasicMessageChannel(
                  name: "flutter/lifecycle",
                  binaryMessenger: registrar.messenger,
                  codec: FlutterStringCodec.sharedInstance()
              )
              lifecycleChannel.sendMessage(event)
          }
      }
  }






  @objc public static func closeRequested(_ window: NSWindow) {
    MultiWindowManager.shared.markWindowClosing(window)
    if let instance = instances.object(forKey: window) {
        let handle = Int(bitPattern: Unmanaged.passUnretained(window).toOpaque())
        instance.channel.invokeMethod("closeRequested", arguments: ["handle": handle])
    }
  }

  // MARK: - Backward Compatibility (Deprecated)
  
  public typealias OnOpenNewWindow = (String?, [String: Any]?, NSSize?, NSPoint?) -> Void
  
  @available(*, deprecated, message: "Use MultiWindowManager.shared.openNewWindow instead. This callback will be removed in v2.0.0")
  public static var onOpenNewWindow: OnOpenNewWindow? {
    get { return _legacyCallback }
    set { _legacyCallback = newValue }
  }
  
  private static var _legacyCallback: OnOpenNewWindow?

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "openNewWindow":
        let args = call.arguments as? [String: Any]
        let name = args?["name"] as? String
        let arguments = args?["arguments"] as? [String: Any]
        
        var size: NSSize? = nil
        if let width = args?["width"] as? Double, let height = args?["height"] as? Double {
            size = NSSize(width: width, height: height)
        }
        
        var position: NSPoint? = nil
        if let x = args?["x"] as? Double, let y = args?["y"] as? Double {
            position = NSPoint(x: x, y: y)
        }

        // Use MultiWindowManager to create the window
        DispatchQueue.main.async {
            let window = MultiWindowManager.shared.openNewWindow(
                name: name,
                arguments: arguments,
                size: size,
                position: position
            )
            result(["handle": window.windowHandle])
        }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func updateArguments(_ arguments: [String: Any]?) {
    self.channel.invokeMethod("argumentsChanged", arguments: ["arguments": arguments as Any])
  }


}
