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
