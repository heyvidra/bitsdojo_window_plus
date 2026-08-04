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
