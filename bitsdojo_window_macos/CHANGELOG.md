## 0.4.2
    - Traffic lights are no longer clipped to half their height on macOS 13 and older. A `bitsdojo_window_title_bar_height()` taller than the standard bar centres the buttons past the bottom edge of `NSTitlebarView`/`NSTitlebarContainerView`, which AppKit never grows; macOS 14+ stopped clipping subviews by default so the overflow rendered anyway, but older systems clip — exactly half of each 14pt button survived. Button repositioning now unclips both titlebar levels (`clipsToBounds` via selector — public on 14+, SPI before — plus the layer's `masksToBounds`), changing nothing about geometry or hit-testing on any version.
    - `WindowEffect.disabled` windows are genuinely opaque again. `BitsdojoWindow` hard-wired `isOpaque` to false — the getter lied and the setter swallowed `YES` — so the disabled path's `setOpaque:YES` never landed and every window paid the translucent compositing cost forever. The override now defers to `wantsTransparentBackground`: translucent windows keep swallowing opacity (macOS resets it mid-occlusion and mid-fullscreen), effect-disabled windows report and accept it honestly. The disabled path also walks the Flutter layer tree back to opaque, because the transparent walk's `CAMetalLayer.opaque = NO` writes were permanent and kept CoreAnimation per-pixel blending the whole surface; `forceTransparency` and the fullscreen 10 Hz enforcement are now reserved for windows that actually want a transparent background, so an occlusion or fullscreen cycle can no longer tear the opaque fast path back down. Custom-frame windows still start transparent — hide-on-startup and the white-flash protections depend on it — and nothing changes for transparent/acrylic/mica.
    - Acrylic/Mica's `NSVisualEffectView` now uses `NSVisualEffectStateFollowsWindowActiveState` instead of `NSVisualEffectStateActive`, so the behind-window desktop blur stops re-rendering on every frame while the app is not key — stock macOS behavior for inactive windows.
    - The 10 Hz fullscreen-transition poll timer can no longer leak. It was only stopped in `windowDid{Enter,Exit}FullScreen`, so an OS-aborted transition left it firing forever — and it retains the controller via `target:`. The controller now also stops it from `windowDidFailTo{Enter,Exit}FullScreen:`, and the timer self-terminates after ~5 s of ticks as the belt-and-braces.

## 0.4.1
    - Hide-on-startup can no longer permanently hide a shown window. The alpha-zeroing in `BitsdojoWindow.order()` used to re-fire on every later orderFront whenever `windowCanBeShown` read false, so a controller lost to a startup race left the window on screen at alpha 0 forever (shipped as Vidra 1.11.x's invisible desktop pet — CI-built binaries only). `showWindow` now latches `hasEverBeenShown` on the window and re-registers a missing controller; the zeroing branch respects the latch and NSLogs when it fires.

## 0.4.0
    - Channel-exposed the existing `MultiWindowManager.closeWindow(named:)`/`getWindow(named:)` as `closeWindow`/`hasWindow`, and broadcast `windowClosed` to every remaining window's engine from the manager's willClose handling — fired only when the closing window is still the name's current holder.

## 0.3.2
    - Window presentation is revived after the screens wake: a long display sleep (or one that reconfigures an external monitor) could leave an unfocused window's CAMetalLayer presenting a stale surface forever — the engine and Dart side kept running (input handled, timers firing) but the window never showed a new pixel. On NSWorkspace.screensDidWakeNotification every visible tracked window is nudged 1pt and restored, driving a full metrics→render→present cycle that re-creates the drawables; contentsScale is re-asserted first for monitors that return at a different scale factor.

## 0.3.1
    - Window geometry now uses one GLOBAL desktop coordinate space (primary screen top-left is (0,0), y down) across get/set/screen-info — fixes windows landing on the wrong display, mid-animation "flying", and save/restore re-basing on multi-monitor setups. Note: `position.dy` readings shift by the menu-bar height relative to prior versions (they now measure from the screen top); positions persisted by older versions restore slightly low.
    - `size` setter keeps the top-left fixed (was AppKit bottom-left anchoring) and updates the frame cache synchronously, matching the animated resize path.
    - Frame cache stays in sync on window moves and display rearrangement (new windowDidMove / screen-parameters observers); fixed a use-after-free reading FFI structs after return (NaN frame crash) and a double-dispatch that let a later resize apply before an earlier move.
    - Restored positions that land on no attached display fall back to centering.

## 0.3.0
    - Secondary windows launch their engine with `--bdw-name=`/`--bdw-args=` dart entrypoint arguments (JSON pre-encoded on the Dart side for int/double fidelity).
    - Plugin registration on secondary engines is now guaranteed: synchronous window-class adoption, the new `MultiWindowManager.pluginRegistrant` hook, and a BitsdojoWindowPlugin fallback — no more MissingPluginException or leaked engines for plain windows.
    - `autoDetectPrimaryWindow` is one-shot and never selects a tracked secondary window.
    - Close tracking no longer grows unboundedly, a Dart-vetoed close no longer poisons named-window reuse, and a replacement same-named window survives the old window's close.
    - macOS deployment target raised to 12.0.

## 0.2.0
    - Fixed `scaleFactor` to return the native backing scale on Retina and mixed-DPI displays.
    - Added native support for reading `titleBarButtonSize`.
    - Made named-window reuse safer during close cycles and improved multi-display position translation.
    - Added `BitsdojoWindowAppDelegate` to reduce macOS runner boilerplate for multi-window apps.

## 0.1.4
    - Various fixes to work with latest Flutter version
## 0.1.3
    - Updated ffi to 2.0.0
## 0.1.2
    - Flutter 3.0 support
## 0.1.0
    - Added null safety support
## 0.0.3

* macOS support on pair with Windows support
## 0.0.2

* Upgraded to ffi 1.0.0

## 0.0.1

* Inital macOS release.
