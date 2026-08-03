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
