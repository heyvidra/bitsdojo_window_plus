## 0.5.0
    - **Breaking:** SDK floor now Dart 3.0 / Flutter 3.10; FFI `Struct` subclasses are `final`.
    - Window events. The already-connected `configure-event` handler now also emits moved / resized, comparing against the geometry it last recorded so the many configure-events that change neither stay silent; `window-state-event` supplies minimized / maximized / restored from `changed_mask`; and `focus-in-event` / `focus-out-event` share one handler that reads the direction off the event. No window handle travels with these: a Linux secondary window is its own process, so an engine only ever reports its own window.
    - `getDisplays()` from `gdk_display_get_monitor`, using each monitor's geometry, work area and scale factor. Wayland has no primary-monitor concept, so when GDK reports none the first monitor is marked primary rather than leaving the app with no primary at all.
    - `showNativeAlert` / `showNativeMenu` implemented in `native_ui.cpp`. The alert is a `GtkMessageDialog` transient for the calling engine's window, with each button's response id set to its index so `gtk_dialog_run` hands the index straight back; `gtk_dialog_set_default_response(dialog, 0)` makes Return pick `buttons[0]`, matching NSAlert and `MessageBoxW`. The menu is a `GtkMenu` popped with `gtk_menu_popup_at_rect` (or `_at_pointer` with no position) and made synchronous by a nested `GMainLoop`: GTK emits the shell's `deactivate` *before* the picked item's `activate`, so the quit is deferred to an idle callback and the id is always recorded first. An empty menu returns early rather than waiting on a `deactivate` that would never arrive. Verified at runtime under Xvfb: alert index and menu id both round-trip.
    - **Breaking:** removed the deprecated `bitsdojo_window_set_on_open_new_window` C entry point and its `TOnOpenNewWindowCallback` typedef. The stored callback was never invoked, so the export advertised a hook that could not fire. Use `MultiWindowManager` instead.
    - Deleted `debug_helper.cpp` — `printWindowStateMask` / `printGdkEvent` had no callers other than one commented-out line, and were still being compiled into the plugin.

## 0.4.3
    - Version alignment with the 0.4.3 macOS launch-crash fix; no functional change in this package.

## 0.4.2
    - Version alignment with the 0.4.2 macOS traffic-light clipping fix; no functional change in this package.

## 0.4.1
    - Version alignment with the 0.4.1 macOS hide-on-startup fix; no functional change in this package.

## 0.4.0
    - `hasWindow`/`closeWindow` degrade to their documented defaults (false / no-op): Linux multi-window launches a separate process per window, so there is no in-process registry to query or close through.

## 0.3.1
    - The position setter un-anchors the window (explicit position wins over sticky alignment on subsequent resizes).

## 0.3.0
    - Child window processes are reaped on exit (no more zombie processes).
    - Spawn environment is scrubbed of inherited BDW_* identity/geometry; unnamed grandchildren no longer inherit a stale route, unpositioned children are centered instead of pinned to the origin.
    - Removed hardcoded MDK_* exports and unconditional software-GL; opt in with BDW_CHILD_WINDOW_SOFTWARE_RENDERING=1 where GL drivers require it.

## 0.2.0
    - Fixed a native memory leak when updating the window title.
    - Implemented `toggleFullScreen()` using GTK fullscreen APIs.
    - Allowed `minSize` and `maxSize` constraints to be cleared again.
    - Simplified Linux multi-window runner integration in the example and README.

## 0.1.4
    - Various fixes to work with latest Flutter version
## 0.1.3
    - Updated ffi to 2.0.0
## 0.1.2
    - Flutter 3.0 support
## 0.1.1
    - Linux support now stable
## 0.1.0+1
    - Fix gtk library name
## 0.1.0
    - Added null safety support
## 0.0.1

    * Initial Linux release
