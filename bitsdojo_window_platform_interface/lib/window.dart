import 'dart:async';
import 'dart:convert' show jsonEncode;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'bitsdojo_window_platform_interface.dart';

int _autoNameCounter = 0;

/// A process-unique name for a window the caller didn't name. Timestamp plus
/// a per-isolate counter: two engines share neither, so names can't collide
/// across the engines (or, on Linux, processes) of one app.
String _autoWindowName() =>
    'bdw#${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '-${_autoNameCounter++}';

class _WindowChangeNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class DesktopWindowCapabilities {
  const DesktopWindowCapabilities({
    this.supportsBackgroundEffects = false,
    this.supportsTitleBarButtonVisibility = false,
    this.supportsTitleBarButtonOffset = false,
  });

  final bool supportsBackgroundEffects;
  final bool supportsTitleBarButtonVisibility;
  final bool supportsTitleBarButtonOffset;
}

enum WindowEffect {
  disabled,
  transparent,
  acrylic,
  mica,
  tabbed,
}

/// Wire-level modality for `BitsdojoWindowPlatform.openNewWindow`. The
/// public API is `DesktopWindow.openDialog` (with a plain `modal:` flag);
/// this enum exists so platform implementations and the channel share one
/// vocabulary.
///
/// The parent is always the *calling* window — the engine that invokes the
/// open — mirroring how `showNativeAlert` parents its sheet.
///
/// Crosses the channel as [Enum.name] (`'modeless'` / `'modal'`; `none`
/// is omitted), so renaming a value is a wire-format break. The names are
/// pinned by a test in the platform interface package.
enum WindowModality {
  /// An independent top-level window — the default.
  none,

  /// A modeless dialog: owned by the opening window, so it stays above it
  /// and minimizes with it, but the opener remains fully interactive.
  ///
  /// On macOS the dialog also follows the parent when the parent moves —
  /// that is how AppKit child windows behave, and fighting it would cost
  /// more than the platform difference is worth.
  modeless,

  /// A modal dialog: owned like [modeless], and the opening window cannot
  /// be interacted with until this window closes.
  ///
  /// Only the *opening* window is blocked (window-modal, not app-modal).
  /// On Linux, where each window is a separate process, the parent's
  /// input is blocked and re-enabled when the dialog's process exits;
  /// above-parent stacking is honored on X11 but not enforceable on
  /// Wayland.
  modal,
}

abstract class DesktopWindow {
  DesktopWindow();

  final _WindowChangeNotifier _changes = _WindowChangeNotifier();

  /// Notifies whenever this window's identity or arguments change — e.g.
  /// when the native `windowReady` message delivers name/arguments after
  /// engine startup, or `updateArguments` targets an existing named window.
  /// Multi-listener alternative to the single-slot [onArgumentsChanged].
  ///
  /// Platform implementations currently fire this only on the engine's own
  /// `appWindow`; proxy instances from `getWindowForHandle` expose the
  /// Listenable but receive no notifications.
  Listenable get changes => _changes;

  /// For platform implementations: signals [changes] listeners that this
  /// window's identity or arguments were updated.
  void notifyWindowChanged() => _changes.notify();

  final StreamController<WindowEvent> _events =
      StreamController<WindowEvent>.broadcast();

  /// What the OS did to this window: focus, move, resize, minimize, maximize,
  /// restore. Broadcast, so several listeners can subscribe, and events that
  /// arrive with nobody listening are dropped rather than buffered.
  ///
  /// Never closed — a window object lives as long as its engine — so there is
  /// nothing to dispose. Cancel your own subscriptions as usual.
  ///
  /// Closing is not here on purpose: use [onClose] to veto a close, and
  /// top-level `onWindowClosed` to hear about other windows closing.
  Stream<WindowEvent> get events => _events.stream;

  /// For platform implementations: publishes an event to [events].
  void emitWindowEvent(WindowEvent event) => _events.add(event);

  int? get handle;

  /// What the DISPLAY reports about itself: DPI/96 on Windows, the Retina
  /// backing scale on macOS.
  ///
  /// A property of the screen, NOT a conversion factor — the two only coincide
  /// on Windows. Converting coordinates with this turns every point on a
  /// Retina Mac into half of itself. Use [coordinateScale] for that.
  double get scaleFactor;

  /// Multiply a LOGICAL coordinate by this to get what [rect], [position] and
  /// `animateTo` actually speak on this platform. Divide to come back.
  ///
  /// 1.0 on macOS and Linux, where those APIs are already in points, and
  /// DPI/96 on Windows, where they are raw device pixels. That split is the
  /// whole reason this exists apart from [scaleFactor]: every caller needing
  /// it was re-deriving it — one inside this package, one in an app on top of
  /// it — and each had to know for itself which platforms lie.
  ///
  /// Measured rather than assumed: [size] is logical everywhere and [rect] is
  /// not, so their ratio IS this number. Cross-checked against [scaleFactor],
  /// which is exact where the ratio is a rounded division. Falls back to 1.0
  /// whenever the window cannot be measured — the answer that leaves
  /// coordinates untouched.
  double get coordinateScale {
    final logicalWidth = size.width;
    final physicalWidth = rect.width;
    if (logicalWidth <= 0 || physicalWidth <= 0) return 1.0;

    final inferred = physicalWidth / logicalWidth;
    if (!inferred.isFinite || inferred <= 0) return 1.0;
    if ((inferred - 1).abs() < 0.01) return 1.0;

    final reported = scaleFactor;
    if (reported > 0 && (inferred - reported).abs() < 0.05) return reported;
    return inferred;
  }

  DesktopWindowCapabilities get capabilities =>
      const DesktopWindowCapabilities();

  Rect get rect;
  set rect(Rect newRect);

  Offset get position;
  set position(Offset newPosition);

  Size get size;
  set size(Size newSize);

  set minSize(Size? newSize);
  set maxSize(Size? newSize);

  Size get screenSize;
  Size get workingScreenSize;
  Rect get workingScreenRect;

  Alignment? get alignment;
  set alignment(Alignment? newAlignment);

  set title(String newTitle);

  bool get isVisible;
  void show();
  void hide();
  void close();
  void minimize();
  void maximize();
  void maximizeOrRestore();
  void toggleFullScreen();
  void restore();

  void startDragging();

  bool get alwaysOnTop;
  set alwaysOnTop(bool onTop);

  bool get hasShadow;
  set hasShadow(bool value);

  Size get titleBarButtonSize;

  double get titleBarHeight;
  set titleBarHeight(double height);

  double get borderSize;
  bool get isMaximized;
  VoidCallback? get onClose;
  set onClose(VoidCallback? callback);
  VoidCallback? get onArgumentsChanged;
  set onArgumentsChanged(VoidCallback? callback);
  set backgroundEffect(WindowEffect effect);
  bool get isMainWindow;
  int get depth;
  String? get name;
  Map<String, dynamic>? get arguments;

  /// Opens an independent top-level window and returns a [WindowRef]
  /// addressing it. An unnamed window gets an auto-generated name, so the
  /// ref always works — before this, an unnamed window was unreachable the
  /// moment this call returned.
  ///
  /// Completion means the open request was accepted, not that the window
  /// finished appearing (window creation is deferred on some platforms).
  /// Opening a name that already exists focuses that window and delivers
  /// [arguments] to it instead of opening a second one.
  ///
  /// For dialogs — owned by this window, optionally modal, with a result —
  /// use [openDialog] instead.
  Future<WindowRef> openNewWindow({
    String? name,
    Size? size,
    Offset? position,
    Map<String, dynamic>? arguments,
  }) async {
    final effectiveName = name ?? _autoWindowName();
    await BitsdojoWindowPlatform.instance.openNewWindow(
      name: effectiveName,
      size: size,
      position: position,
      arguments: arguments,
    );
    return WindowRef(effectiveName);
  }

  /// Opens a dialog owned by THIS window and completes when it closes, with
  /// whatever the dialog passed to [closeWithResult] — or null when it was
  /// closed without a result (its close button, [WindowRef.close], Esc).
  ///
  /// The receiver is the parent: the dialog stays above this window and, when
  /// [modal] (the default), this window takes no input until it closes.
  /// Modality is window-modal, never app-modal. Calling again with a [name]
  /// that is still open focuses the existing dialog and returns the same
  /// future rather than opening a second one.
  ///
  /// Platform honesty: on macOS the dialog also follows this window when it
  /// moves (AppKit child windows do). On Linux — one process per window —
  /// the input block and the result channel always work, above-parent
  /// stacking only holds on X11, and calling openDialog again with the name
  /// of a dialog that is STILL OPEN resolves the pending future with null
  /// (the focus-the-existing-window forwarder process exiting is
  /// indistinguishable from the dialog closing).
  Future<Map<String, dynamic>?> openDialog({
    String? name,
    Size? size,
    Offset? position,
    Map<String, dynamic>? arguments,
    bool modal = true,
  }) async {
    final effectiveName = name ?? _autoWindowName();
    final result = WindowCloseHub.registerDialog(effectiveName);
    try {
      await BitsdojoWindowPlatform.instance.openNewWindow(
        name: effectiveName,
        size: size,
        position: position,
        arguments: arguments,
        modality: modal ? WindowModality.modal : WindowModality.modeless,
      );
    } catch (error, stackTrace) {
      WindowCloseHub.abortDialog(effectiveName, error, stackTrace);
    }
    return result;
  }

  /// Closes this window, delivering [result] to the `openDialog` call that
  /// opened it. In a window nobody is awaiting, this is just [close].
  ///
  /// The result is stored before the close is requested, so if an `onClose`
  /// interceptor vetoes the close, a later real close still delivers the
  /// LAST stored result.
  void closeWithResult(Map<String, dynamic> result) {
    // Sequenced, not fired in parallel: the store must be ACKNOWLEDGED by
    // the native side before the close goes out. The two travel on different
    // native queues, and a close that lands first broadcasts null to the
    // awaiting openDialog — observed, not hypothetical, on macOS.
    BitsdojoWindowPlatform.instance
        .setWindowResult(jsonEncode(result))
        .whenComplete(close);
  }

  /// Shows an OS-native alert owned by THIS window — a sheet on macOS, a
  /// window-modal dialog on Windows and Linux — and completes with the index
  /// of the pressed button in [buttons], or -1 if dismissed without one.
  ///
  /// [buttons] is affirmative-first (`['Delete', 'Cancel']`). Windows shows
  /// the system button set for the given count and ignores the labels.
  ///
  /// These native-UI calls route through this engine's channel: on a proxy
  /// window from `getWindowForHandle` they act on the calling engine's own
  /// window, not the proxy's.
  Future<int> showNativeAlert({
    required String title,
    String? message,
    List<String> buttons = const ['OK'],
    NativeAlertStyle style = NativeAlertStyle.info,
  }) =>
      BitsdojoWindowPlatform.instance.showNativeAlert(
        title: title,
        message: message,
        buttons: buttons,
        style: style,
      );

  /// Two-button [showNativeAlert]: true when [confirmLabel] was pressed,
  /// false for [cancelLabel] or a dismissal.
  Future<bool> showNativeConfirm({
    required String title,
    String? message,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    NativeAlertStyle style = NativeAlertStyle.warning,
  }) async =>
      await showNativeAlert(
        title: title,
        message: message,
        buttons: [confirmLabel, cancelLabel],
        style: style,
      ) ==
      0;

  /// Pops up an OS-native menu over THIS window, completing when it closes
  /// with the [NativeMenuItem.id] of the picked entry — or null if dismissed.
  ///
  /// [position] is in logical pixels from this window's top-left, so a
  /// `GestureDetector`'s `details.globalPosition` goes straight through.
  /// Null pops the menu at the mouse pointer.
  Future<String?> showNativeMenu(
    List<NativeMenuItem> items, {
    Offset? position,
  }) =>
      BitsdojoWindowPlatform.instance.showNativeMenu(items, position: position);

  void setWindowTitleBarButtonVisibility(
      DesktopWindowButton button, bool visible) {
    // Reaching this base body means no platform override exists — check
    // capabilities before calling, and be loud about it in debug instead of
    // silently doing nothing.
    assert(
      capabilities.supportsTitleBarButtonVisibility,
      'setWindowTitleBarButtonVisibility is not supported on this platform — '
      'guard the call with '
      'appWindow.capabilities.supportsTitleBarButtonVisibility.',
    );
  }

  void setWindowTitleBarButtonOffset(
      DesktopWindowButton button, Offset offset) {
    assert(
      capabilities.supportsTitleBarButtonOffset,
      'setWindowTitleBarButtonOffset is not supported on this platform — '
      'guard the call with '
      'appWindow.capabilities.supportsTitleBarButtonOffset.',
    );
  }
}

/// A title-bar button.
///
/// Crosses the channel as `button.index`, and macOS casts that integer straight
/// into AppKit's `NSWindowButton` (see `titlebar_button_manager.mm`) — a foreign
/// ABI this package does not control, where 0/1/2 are close/miniaturize/zoom.
/// So: **append only**. Reordering or inserting a value silently retargets which
/// native button gets hidden or moved, with nothing in Dart to catch it. The
/// ordinals are pinned by a test in the platform interface package.
enum DesktopWindowButton {
  close,
  minimize,
  zoom,
}
