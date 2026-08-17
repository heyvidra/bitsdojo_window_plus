// Display geometry shares a coordinate space with `DesktopWindow.position` on
// the SAME platform, which is why its unit is not the same everywhere: device
// pixels on Windows, logical pixels on macOS and Linux. Anything comparing a
// display against a coordinate of its own wants the logical accessors.
//
// The trap these pin is the obvious-looking conversion that is wrong: dividing
// by scaleFactor. Right on Windows, catastrophic on macOS, where the rects are
// already points and scaleFactor is the Retina backing scale — so dividing
// halves every display and puts most stored positions "off-screen".

import 'package:bitsdojo_window_platform_interface/display.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Display _display({required double scaleFactor}) => Display(
      id: '1',
      name: 'Test',
      bounds: const Rect.fromLTWH(0, 0, 2880, 1620),
      workArea: const Rect.fromLTWH(0, 60, 2880, 1500),
      scaleFactor: scaleFactor,
      isPrimary: true,
    );

void main() {
  // The host these run on is macOS/Linux, so the branch under test is the
  // non-Windows one: geometry is already logical and must come back untouched
  // no matter what scaleFactor says.
  test('a Retina scale factor does not shrink the display', () {
    final d = _display(scaleFactor: 2.0);
    expect(d.logicalBounds, d.bounds);
    expect(d.logicalWorkArea, d.workArea);
  });

  test('scaleFactor 1 is identity everywhere', () {
    final d = _display(scaleFactor: 1.0);
    expect(d.logicalBounds, d.bounds);
    expect(d.logicalWorkArea, d.workArea);
  });

  test('a nonsense scale factor cannot produce infinities', () {
    for (final bad in [0.0, -1.0]) {
      final d = _display(scaleFactor: bad);
      expect(d.logicalBounds, d.bounds);
      expect(d.logicalBounds.width.isFinite, isTrue);
    }
  });
}
