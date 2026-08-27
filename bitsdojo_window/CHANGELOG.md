## 0.7.0
    - **One rule for the whole call surface: the receiver carries the meaning.** Anything acting on THIS window is a member of `appWindow`; anything addressing the process or the machine is a member of the new `desktopApp` (`closeWindow(name)`, `hasWindow(name)`, `windowClosed` stream, `displays()`, `terminate()`, `windowForHandle(handle)`). The native-UI calls move onto `appWindow` (`showNativeAlert` / `showNativeConfirm` / `showNativeMenu`) — they always acted on the calling window, and their old top-level placement was the documented exception to the old rule. Every pre-0.7.0 top-level function still works as a one-line `@Deprecated` forwarder; only the bootstrap family (`runBitsdojoWindowApp`, `doWhenWindowReady`, ...) stays top-level, because it runs before the objects mean anything.
    - **`appWindow.openDialog(...)` — dialogs that answer.** Completes when the dialog closes, with whatever the dialog passed to the new `appWindow.closeWithResult(map)` — or null for a plain close. The receiver is the parent: call it on the window that owns the dialog. `modal: true` is the default ("dialog" should mean modal; modeless is the explicit minority); modality is window-modal, never app-modal. The 0.6.0 `openNewWindow(modality:)` parameter was folded into this before ever being published — regular windows go through `openNewWindow`, dialogs through `openDialog`, one entry point per job.
    - **`openNewWindow` returns a `WindowRef`.** Unnamed windows get an auto-generated name, so the window a call opened can always be reached again — `ref.close()`, `ref.exists()`, `ref.update(args)`. Previously an unnamed window was unreachable the moment the call returned (macOS even returned a native handle that the Dart layer dropped on the floor).
    - **`desktopApp.windowClosed` is a broadcast `Stream<String>`,** replacing the single-slot `onWindowClosed` setter (still fired, deprecated). Subscribing from several places is the normal case, and a slot forces callers to build their own fan-out. `appWindow.onClose` deliberately stays a slot: it is an interceptor, and two vetoers cannot both decide one close.
    - Unsupported platform-gated calls now `assert` in debug builds pointing at the `capabilities` flag to check, instead of silently doing nothing.
    - **Removed:** the long-deprecated `visible` getter/setter (use `isVisible` / `show()` / `hide()`).

## 0.6.0
    - `openNewWindow(modality: WindowModality.modeless | .modal)` — dialogs. The parent is always the CALLING window (the engine that invokes the call), the same rule that makes `showNativeAlert` land on the right window in a multi-window app; there is deliberately no way to name some other window as the parent. `modeless` makes the new window owned: it stays above the parent and minimizes with it, while the parent stays interactive. `modal` additionally blocks input to the parent until the dialog closes — window-modal, never app-modal — then re-enables and re-focuses it. Opening a NAMED window that already exists keeps its focus-and-update-arguments behavior and ignores modality.
    - Platform honesty, per the per-platform changelogs: on macOS the dialog also follows the parent when it moves (AppKit child windows do) and clicking the blocked parent beeps and re-fronts the dialog; on Linux — one process per window — the input block always works but above-parent stacking rides `WM_TRANSIENT_FOR` and only holds on X11, not Wayland.

## 0.5.1
    - `animateTo` no longer flashes a blank window on Windows when it moves and resizes at once. DWM repaints a resizing window, and one that is also travelling shows its background while it does. The resize now lands in a single frame up front and only the travel is eased. This was previously left to callers to discover and hand-roll — including the DPI scaling that `set size` handles and a hand-rolled `rect` write has to repeat.
    - The animation's private coordinate-scale derivation is now `DesktopWindow.coordinateScale`.
    - `appWindow` documents the shape of this API: acting on THIS window is a member and synchronous, addressing the process or the machine is a top-level function and asynchronous. So it is `getDisplays()`, never `appWindow.getDisplays()`, and `await appWindow.close()` does not compile while `await closeWindow(name)` does.

## 0.5.0
    - **Breaking:** the SDK floor moves to Dart 3.0 / Flutter 3.10. The window event types below are a closed set worth `sealed`ing so a `switch` over them is checked for exhaustiveness, and that needs Dart 3. The floor is the minimum the feature requires, not the newest release — anything on Dart 3.0 or later still resolves. FFI struct classes in the platform packages are now `final`, which Dart 3 requires of `Struct` subclasses.
    - **`appWindow.alignment = Alignment.bottomLeft` now puts the window on the screen.** It used to land one full window width off the left edge; and any alignment that wasn't one of the nine named constants — `Alignment(0, 0.5)`, say — collapsed the window to zero size at the origin instead of placing it. Same fix applies to `animateTo(alignment: ...)`. See the platform interface changelog for the details.
    - **Breaking (only if you mutated it):** `WindowButtonColors` is immutable — its six fields are `final` and its constructor is `const`. Assigning after construction (`colors.normal = x`) no longer compiles; pass the colors in, or use `copyWith`-style reconstruction. This deletes the `_defaultButtonColors` singleton, which was a shared *mutable* instance reachable through any button's `colors` field: writing to it changed every default-coloured window button in the app. Parameters stay nullable, so `WindowButtonColors(iconNormal: Theme.of(context).iconTheme.color)` still works with a nullable theme color.
    - `WindowBorder` reads `appWindow.scaleFactor` once per build instead of four times. That property is a native call on every platform (`GetDpiForWindow` on Windows), and this widget wraps the whole app, so it rebuilds with the subtree.
    - `appWindow.events` — a broadcast `Stream<WindowEvent>` of what the OS did to this window: `WindowFocused`, `WindowBlurred`, `WindowMoved(position)`, `WindowResized(size)`, `WindowMinimized`, `WindowMaximized`, `WindowRestored`. Geometry arrives in the same logical-pixel space `position` and `size` read back, because every platform fills the payload from the same native getter those properties use — an event can't disagree with a property read that follows it. Closing is deliberately absent: `onClose` can veto a close and top-level `onWindowClosed` reports other windows' closes, and a stream event can do neither.
    - `getDisplays()` — every attached monitor as a `Display` (id, name, bounds, workArea, scaleFactor, isPrimary), in the same coordinate space as `appWindow.position`, so placing a window on a chosen monitor is `appWindow.position = display.workArea.topLeft`. Returns an empty list rather than throwing where the platform can't enumerate.
    - `ContextMenuRegion` — wraps a child so a right-click pops `showNativeMenu` at the pointer, with `onSelected` / `onDismissed`. Takes either a fixed `items` list or an `itemsBuilder` evaluated at click time.
    - System-level dialogs and menus, owned by the calling window: `showNativeAlert(title:, message:, buttons:, style:)` returns the index of the pressed button (-1 when dismissed), `showNativeConfirm(...)` is the two-button shorthand returning a bool, and `showNativeMenu(items, position:)` pops an OS menu and returns the picked `NativeMenuItem` id (null when dismissed). A sheet on macOS, a window-modal dialog on Windows and Linux. These are top-level functions rather than `appWindow` methods because each engine's plugin instance already knows which window it belongs to — which is what makes them land on the right window in a multi-window app, where the generic packages can only target the key window. Prefer Flutter's own `showDialog` / `MenuAnchor` unless the dialog has to be OS-modal, look native, or escape the window bounds.
    - Version alignment with the 0.5.0 removal of deprecated no-op native entry points, and the macOS fullscreen fix for custom-frame windows that never set a background effect.

## 0.4.3
    - Version alignment with the 0.4.3 macOS launch-crash fix; no functional change in this package.

## 0.4.2
    - Version alignment with the 0.4.2 macOS traffic-light clipping fix; no functional change in this package.

## 0.4.1
    - Version alignment with the 0.4.1 macOS hide-on-startup fix; no functional change in this package.

## 0.4.0
    - Window lifecycle by name: top-level `closeWindow(name)` closes a named window (no-op when absent), `hasWindow(name)` reports whether one exists, and the `onWindowClosed` callback fires in every remaining window's engine when a named window closes — however it closed. Previously the only cross-window verb was `openNewWindow`, so dismissing a window meant re-opening it with a payload asking it to close itself.

## 0.3.1
    - `WindowConfiguration.applyTo` applies alignment before size and clears the sticky anchor when the configuration resolves none, so reused windows no longer teleport to a stale anchor before their restored position lands.
    - `animateTo(position:)` and the platform position setters now un-anchor the window (explicit position wins over sticky alignment); `WindowReadyAnimation` re-anchors after the pop-in completes so aligned configs keep re-centering on resize.

## 0.3.0
    - `runBitsdojoWindowApp`/`setupBitsdojoWindow` accept main's `args` and seed window identity from `--bdw-name=`/`--bdw-args=` entrypoint arguments, so `window.name`/`arguments` are correct before the first build (no windowReady race). Added `seedWindowIdentityFromArgs` and `withoutWindowIdentityArgs`.
    - `RoutedWindowHost` re-evaluates the route when the window's identity changes; child windows can no longer get stuck on the default route.
    - `WindowEventListener` releases the single-slot callbacks only when it still owns them, and never hands a defunct BuildContext to a close interceptor. A close confirmed by the interceptor is honored even if the listener unmounted during the await.
    - `animateTo` uses a monotonic clock (immune to wall-clock jumps).
    - Requires Flutter >=3.0.0.

## 0.2.0
    - Added `runBitsdojoWindowApp`, `setupBitsdojoWindow`, `WindowEventListener`, and `RoutedWindowHost` to simplify Flutter-side integration.
    - Updated examples and README to use the new high-level integration helpers.
    - Replaced the stale example widget test with a plugin-safe test setup.
    - Modernized deprecated Flutter API usage in window button widgets.

## 0.1.6
    - Various fixes to work with latest Flutter version
## 0.1.5
    - Runs on Windows 7
## 0.1.4
    - Updated win32 to 3.0.0
## 0.1.3
    - Updated ffi to 2.0.0
## 0.1.2
    - Flutter 3.0 support
## 0.1.1+1
    - Added Linux usage instructions
## 0.1.1
    - Linux support now stable
## 0.1.0+1
    - Fix gtk library name on Linux
## 0.1.0
    - Added null safety support
## 0.0.9
    - Linux support added
## 0.0.8
    - Added macOS readme instructions
## 0.0.7
    - macOS support added
## 0.0.6
    - Works with latest Flutter version (master channel)
## 0.0.5
    - Works with latest Flutter version (dev channel)
## 0.0.4
    - Better integration with other plugins
## 0.0.3
    - Using dpi-aware values for title bar and buttons dimensions
    - Dynamically calculating default button padding instead of fixed one
## 0.0.2
    - Added video tutorial link
## 0.0.1

* Initial release
    - Custom window frame - remove standard Windows titlebar and buttons
    - Hide window on startup
    - Show/hide window
    - Minimize/Maximize/Restore/Close window
    - Move window using Flutter widget
    - Set window size, minimum size and maximum size
    - Set window position
    - Set window alignment on screen (center/topLeft/topRight/bottomLeft/bottomRight)
    - Set window title
