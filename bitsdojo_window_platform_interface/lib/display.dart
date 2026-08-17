import 'dart:ui' show Rect;

/// One monitor attached to the machine.
///
/// [bounds] and [workArea] are in logical pixels and share their coordinate
/// space with `DesktopWindow.position`, so a window can be placed on a chosen
/// display with `window.position = display.workArea.topLeft`.
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
