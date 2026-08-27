import 'dart:async';
import 'dart:convert' show jsonDecode;

import 'bitsdojo_window_platform_interface.dart';

/// Central dispatch for "a window closed" notifications in this engine.
///
/// Platform implementations call [notifyClosed] when their native side
/// reports a close; everything that cares fans out from here:
/// the public `desktopApp.windowClosed` stream, a pending `openDialog`
/// future waiting on that window's result, and the legacy single-slot
/// `BitsdojoWindowPlatform.onWindowClosed` callback. Centralized so the
/// three consumers can't drift apart per platform.
class WindowCloseHub {
  WindowCloseHub._();

  static final StreamController<String> _closed =
      StreamController<String>.broadcast();

  static final Map<String, Completer<Map<String, dynamic>?>> _pendingDialogs =
      {};

  /// Names of windows that closed, however they closed. Process-wide on
  /// Windows and macOS; on Linux — one process per window — only windows
  /// this window spawned are reported.
  static Stream<String> get closed => _closed.stream;

  /// Registers interest in [name]'s close-with-result. Calling again for a
  /// name that is still pending returns the SAME future: `openDialog` with
  /// an existing name focuses the existing dialog rather than opening a
  /// second one, so both callers are waiting on the same window.
  static Future<Map<String, dynamic>?> registerDialog(String name) {
    return _pendingDialogs
        .putIfAbsent(name, Completer<Map<String, dynamic>?>.new)
        .future;
  }

  /// Drops a pending registration whose open never happened (the
  /// `openNewWindow` call threw). Completes the future with [error] so the
  /// caller's await fails instead of hanging forever.
  static void abortDialog(String name, Object error, StackTrace stackTrace) {
    final pending = _pendingDialogs.remove(name);
    if (pending != null && !pending.isCompleted) {
      pending.completeError(error, stackTrace);
    }
  }

  /// For platform implementations: [name] closed, carrying [resultJson] when
  /// its Dart called `closeWithResult` (null for a plain close or dismissal).
  ///
  /// A result that fails to parse completes the dialog with null rather than
  /// throwing: the window is already gone, and the awaiting caller can only
  /// act on "no result".
  static void notifyClosed(String name, [String? resultJson]) {
    final pending = _pendingDialogs.remove(name);
    if (pending != null && !pending.isCompleted) {
      Map<String, dynamic>? result;
      if (resultJson != null) {
        try {
          result = jsonDecode(resultJson) as Map<String, dynamic>;
        } catch (_) {
          result = null;
        }
      }
      pending.complete(result);
    }

    _closed.add(name);
    BitsdojoWindowPlatform.instance.onWindowClosed?.call(name);
  }
}
