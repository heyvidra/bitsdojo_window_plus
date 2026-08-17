## 0.5.1
    - `Display.logicalBounds` / `logicalWorkArea`. The raw `bounds`/`workArea` share a coordinate space with `DesktopWindow.position` on the SAME platform, which is what they are for, and is why their unit differs: device pixels on Windows, points on macOS and Linux. Anything comparing them against a coordinate of its own — a window position remembered across restarts — needs logical units on every platform, and the obvious conversion is a trap: dividing by `scaleFactor` is right on Windows and halves every display on a Retina Mac, where the rects are already points and the factor is the backing scale. The class doc also claimed the rects were logical everywhere, which stopped being true in 0.5.0.
    - `DesktopWindow.coordinateScale`: multiply a logical coordinate by it to get what `rect`, `position` and `animateTo` speak on this platform. 1.0 on macOS and Linux, DPI/96 on Windows. Two separate copies of this derivation existed — one in this package's animation code, one in an application on top of it — because `scaleFactor` looks like it should serve and does not.

## 0.5.0
    - **Window placement fix, affects all three platforms.** `getRectOnScreen` — which backs `window.alignment` and the aligned form of `animateTo` — placed `Alignment.bottomLeft` one full window width off the left edge of the screen: it subtracted the window width from the screen's LEFT edge (the local was even named `bottomRight`). Any `Alignment` outside the nine named constants was worse: it fell through to `Rect.zero`, collapsing the window instead of positioning it. The 64-line chain of hand-written cases is now a call to Flutter's own `Alignment.inscribe`, which is the same arithmetic done right for every alignment. Verified by execution: the other eight named alignments were already bit-identical to `inscribe`, so nothing else moves. The function had no test coverage, which is how this survived; it now has four.
    - `DesktopWindowButton` documents that its ordinals are cast straight into AppKit's `NSWindowButton`, so the enum is append-only. Tests now pin the wire values of `DesktopWindowButton`, `NativeAlertStyle` and `WindowEventCode` to their literals — the previous style assertion compared `.index` against `.index`, which is the enum against itself and would have survived exactly the renumbering it looked like it was guarding.
    - **Breaking:** SDK floor now Dart 3.0 / Flutter 3.10, so `WindowEvent` can be `sealed`.
    - `DesktopWindow.events` (a broadcast `Stream<WindowEvent>`) with `emitWindowEvent` for platform implementations, mirroring the existing `changes` / `notifyWindowChanged` pair. The controller is never closed — a window object lives as long as its engine — so there is nothing to dispose. `decodeWindowEvent` parses the shared `windowEvent` channel payload and returns null for a code it doesn't know, so a newer native layer can add events without breaking an older Dart side.
    - `Display` + `BitsdojoWindowPlatform.getDisplays()`, implemented over the shared channel in `MethodChannelBitsdojoWindow`. `Display.fromMap` drops an entry with no bounds and treats a missing work area as "the whole display".
    - Native dialog/menu surface: `BitsdojoWindowPlatform.showNativeAlert(...)` and `showNativeMenu(...)`, plus the `NativeMenuItem` / `NativeAlertStyle` types. Both default to delegating to `MethodChannelBitsdojoWindow`, which implements them over the shared `bitsdojo/window` channel and swallows `MissingPluginException` into the neutral result (-1 / null) — so a platform without native UI reads as a dismissal rather than throwing, and callers only ever branch on the value.
    - Version alignment with the 0.5.0 removal of deprecated no-op native entry points.

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
