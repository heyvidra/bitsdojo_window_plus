## 0.4.3
    - Version alignment with the 0.4.3 macOS launch-crash fix; no functional change in this package.

## 0.4.2
    - Version alignment with the 0.4.2 macOS traffic-light clipping fix; no functional change in this package.

## 0.4.1
    - Version alignment with the 0.4.1 macOS hide-on-startup fix; no functional change in this package.

## 0.4.0
    - Added `hasWindow(name)` (defaults to false), `closeWindow(name)` (defaults to a no-op) and the `onWindowClosed` callback slot to `BitsdojoWindowPlatform`. Defaults are graceful rather than throwing: "no such window" is the correct answer on platforms without multi-window support.

## 0.3.0
    - Added `DesktopWindow.changes` (multi-listener `Listenable`) and `notifyWindowChanged()` for windowReady/updateArguments notifications.
    - Added `BitsdojoWindowPlatform.seedWindowIdentity` for identity known at engine startup.
    - Requires Flutter >=3.0.0.

## 0.2.0
    - Removed an invalid override annotation from the platform interface.

## 0.1.2
    - Flutter 3.0 support
## 0.1.0
    - Added null safety support
## 0.0.2
    - New release for macOS support
## 0.0.1
    - Initial release
