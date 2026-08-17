import 'package:flutter/painting.dart';

/// The rect a window of [sizeOnScreen] occupies when anchored by [alignment]
/// inside [screenRect].
///
/// This used to be a chain of hand-written cases per named Alignment, which had
/// two defects: `bottomLeft` subtracted the window width from the screen's LEFT
/// edge, placing the window one full width off-screen, and any Alignment that
/// wasn't one of the nine named constants fell through to `Rect.zero` — so
/// `Alignment(0, 0.5)` collapsed the window instead of placing it. Flutter's own
/// `Alignment.inscribe` is the same arithmetic done right, for every alignment.
Rect getRectOnScreen(Size sizeOnScreen, Alignment alignment, Rect screenRect) =>
    alignment.inscribe(sizeOnScreen, screenRect);
