import 'dart:ffi';
import './native_struct.dart';
import 'package:flutter/painting.dart';
import './native_api.dart';

/// The screen a window sits on: its full bounds and the part left over once the
/// menu bar and Dock are excluded.
///
/// A record rather than a class with two nullable fields — both are always
/// assigned, on the failure path too, so the null checks callers used to write
/// were dead code that only made every read need a `!`.
typedef ScreenInfo = ({Rect workingRect, Rect fullRect});

ScreenInfo getScreenInfoForWindow(int window) {
  final ok = getScreenInfoNative(window, _scratchScreenInfo);
  if (!ok) {
    assert(false);
    return (workingRect: Rect.zero, fullRect: Rect.zero);
  }
  // Dereferenced only after the call reports success: on failure native leaves
  // whatever the previous call wrote in the shared struct.
  final workingRect = _scratchScreenInfo.ref.workingRect.ref;
  final fullRect = _scratchScreenInfo.ref.fullRect.ref;
  return (
    workingRect: Rect.fromLTRB(workingRect.left, workingRect.top,
        workingRect.right, workingRect.bottom),
    fullRect: Rect.fromLTRB(
        fullRect.left, fullRect.top, fullRect.right, fullRect.bottom),
  );
}

/// One scratch struct for every rect that crosses to native, instead of a
/// calloc/free pair per call.
///
/// Geometry moves on hot paths: `animateTo` writes a rect every frame, and
/// `size` / `position` each read one — from inside widget builds, in the case of
/// the title-bar widgets. Every one of those was a heap round trip for 32 bytes
/// that native fills in and Dart reads back immediately.
///
/// Sharing it is safe because these calls are synchronous FFI that never
/// re-enters Dart: nothing else can run between the native write and the read
/// below it. Like the rest of this API, it assumes the main isolate.
final Pointer<BDWRect> _scratchRect = newBDWRect();

/// Same reasoning as [_scratchRect], for the same reason it is safe. This one is
/// three allocations per call rather than one — the struct plus the two rects it
/// points at — though it is read once per alignment change rather than per
/// frame, so this is consistency more than speed.
final Pointer<BDWScreenInfo> _scratchScreenInfo = newBDWScreenInfo();

Rect getRectForWindow(int window) {
  final bdwResult = getRectForWindowNative(window, _scratchRect);
  if (bdwResult != BDW_SUCCESS) {
    assert(false);
    return Rect.zero;
  }
  return Rect.fromLTRB(_scratchRect.ref.left, _scratchRect.ref.top,
      _scratchRect.ref.right, _scratchRect.ref.bottom);
}

void setRectForWindow(int window, Rect newRect) {
  _scratchRect.ref
    ..left = newRect.left
    ..top = newRect.top
    ..right = newRect.right
    ..bottom = newRect.bottom;
  setRectForWindowNative(window, _scratchRect);
}
