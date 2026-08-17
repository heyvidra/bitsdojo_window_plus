import 'dart:io' show Platform;
import 'dart:ui' show Rect;

/// One monitor attached to the machine.
///
/// [bounds] and [workArea] share a coordinate space with
/// `DesktopWindow.position` ON THE SAME PLATFORM — that is what they are for,
/// and it is why their UNIT is not the same everywhere: device pixels on
/// Windows, where `position` is GetWindowRect/SetWindowPos and neither scales,
/// and logical pixels on macOS and Linux.
///
/// Anything comparing them against a coordinate of its own — a window position
/// remembered across restarts, say — wants [logicalBounds] and
/// [logicalWorkArea], which are logical pixels on every platform.
class Display {
  const Display({
    required this.id,
    required this.name,
    required this.bounds,
    required this.workArea,
    required this.scaleFactor,
    required this.isPrimary,
  });

  /// Stable for as long as the display stays attached. Opaque — the platforms
  /// have nothing in common here beyond "a string that identifies it".
  final String id;
  final String name;

  /// The whole display.
  final Rect bounds;

  /// [bounds] minus the space the OS reserves — menu bar, taskbar, docks.
  final Rect workArea;

  final double scaleFactor;
  final bool isPrimary;

  /// [bounds] in logical pixels on every platform.
  Rect get logicalBounds => _toLogical(bounds);

  /// [workArea] in logical pixels on every platform.
  Rect get logicalWorkArea => _toLogical(workArea);

  /// The platform split, resolved HERE so no caller has to carry it.
  ///
  /// It is not "divide by [scaleFactor]": that is right on Windows and wrong
  /// on macOS, where the rects arrive as NSScreen points while [scaleFactor]
  /// carries the Retina backing scale — dividing there would halve every
  /// display on the machine and put most stored positions off-screen.
  Rect _toLogical(Rect r) {
    if (!Platform.isWindows || scaleFactor <= 0 || scaleFactor == 1.0) return r;
    return Rect.fromLTRB(
      r.left / scaleFactor,
      r.top / scaleFactor,
      r.right / scaleFactor,
      r.bottom / scaleFactor,
    );
  }

  static Display? fromMap(Map<Object?, Object?> map) {
    final bounds = _rect(map, 'x', 'y', 'width', 'height');
    if (bounds == null) return null;
    return Display(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      bounds: bounds,
      // A platform that can't report a work area is better described as
      // "work area == the whole display" than as no display at all.
      workArea: _rect(map, 'workX', 'workY', 'workWidth', 'workHeight') ??
          bounds,
      scaleFactor: (map['scaleFactor'] as num?)?.toDouble() ?? 1.0,
      isPrimary: map['isPrimary'] as bool? ?? false,
    );
  }

  static Rect? _rect(
    Map<Object?, Object?> map,
    String x,
    String y,
    String width,
    String height,
  ) {
    final left = (map[x] as num?)?.toDouble();
    final top = (map[y] as num?)?.toDouble();
    final w = (map[width] as num?)?.toDouble();
    final h = (map[height] as num?)?.toDouble();
    if (left == null || top == null || w == null || h == null) return null;
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  String toString() =>
      'Display($id, $name, bounds: $bounds, workArea: $workArea, '
      'scale: $scaleFactor${isPrimary ? ', primary' : ''})';
}
