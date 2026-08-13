## 0.4.0
    - Channel-exposed `MultiWindowManager::CloseWindow/GetWindow` as `closeWindow`/`hasWindow`, and broadcast `windowClosed` via per-window closed notifiers. The broadcast fires from both close paths — `CloseWindow` erases the name mapping before `DestroyWindow`, so it announces the close itself, while user-initiated closes announce from `OnWindowDestroyed`; the two can never double-fire for one close.

## 0.3.1
    - The position setter un-anchors the window (explicit position wins over sticky alignment on subsequent resizes).

## 0.3.0
    - Per-window cleanup now runs from the plugin's own WM_NCDESTROY hook, fixing MultiWindowManager bookkeeping that silently leaked (the stock runner template nulls the HWND before OnDestroy).
    - `CloseWindow` no longer holds a map iterator across DestroyWindow (undefined behavior once re-entrant cleanup works).
    - The runner window factory should pass `--bdw-name=`/`--bdw-args=` via `set_dart_entrypoint_arguments` (see example) so child windows know their identity at startup.

## 0.2.0
    - Allowed `minSize` and `maxSize` constraints to be cleared again.
    - Improved multi-window lifecycle cleanup for destroyed child windows.
    - Replaced the single pending child-window metadata slot with queue-based handoff.
    - Documented the minimum Windows runner glue for multi-window apps.

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
## 0.1.0
    - Added null safety support
## 0.0.3

* Deprecated some methods
## 0.0.2

* Upgraded to ffi 1.0.0 and win32 2.0.0
## 0.0.1

* Initial Windows release as federated plugin
