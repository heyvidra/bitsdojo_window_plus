## 0.5.0
    - `showNativeAlert` / `showNativeMenu` implemented in `native_ui.cpp`. The alert is a `MessageBoxW` owned by the calling engine's top-level window, so it is window-modal rather than freezing the app. **`MessageBoxW` only offers the fixed system button sets, so the button *count* selects the set — 1 → OK, 2 → OK+Cancel, 3+ → Yes+No+Cancel — and the caller's labels are ignored**; honouring custom labels would mean `TaskDialogIndirect`, which needs a comctl32 v6 manifest entry the Flutter runner template does not ship. The default button stays `buttons[0]`, matching the other platforms. The menu is a `CreatePopupMenu` tree shown with `TrackPopupMenuEx(TPM_RETURNCMD)`, which blocks until dismissed and hands back a 1-based command id mapped to the Dart-side item id; positions are converted from Flutter's logical pixels using `GetDpiForWindow` and `ClientToScreen` on the Flutter child window.
    - **Note:** the Windows implementation is compile-verified only — both translation units build clean against real Win32 headers (`-Wall -Wextra`, `_WIN32_WINNT=0x0A00`) and the Flutter embedder headers, but no Windows host was available to exercise the dialogs at runtime. `example/lib/native_ui_check.dart` is the harness for that: `flutter run -d windows -t lib/native_ui_check.dart` should print `CHECK alert index=0` and `CHECK menu picked=copy`.
    - **Breaking:** removed the deprecated `bitsdojo_window_set_on_open_new_window` C entry point and its `TOnOpenNewWindowCallback` typedef. The stored callback was never invoked — the function only logged a deprecation warning — so the export advertised a hook that could not fire. Use `MultiWindowManager` instead.

## 0.4.3
    - Version alignment with the 0.4.3 macOS launch-crash fix; no functional change in this package.

## 0.4.2
    - Version alignment with the 0.4.2 macOS traffic-light clipping fix; no functional change in this package.

## 0.4.1
    - Version alignment with the 0.4.1 macOS hide-on-startup fix; no functional change in this package.

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
