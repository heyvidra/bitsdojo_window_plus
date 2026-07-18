import 'dart:async';

import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

final Map<Object, _WindowAnimationSession> _windowAnimationSessions = {};

extension DesktopWindowAnimation on DesktopWindow {
  Future<void> animateTo({
    Size? size,
    Offset? position,
    Alignment? alignment,
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
  }) {
    assert(
      position == null || alignment == null,
      'Provide either position or alignment, not both.',
    );

    if (size == null && position == null && alignment == null) {
      return Future<void>.value();
    }

    if (duration <= Duration.zero) {
      if (size != null) {
        this.size = size;
      }
      if (position != null) {
        this.position = position;
      }
      if (alignment != null) {
        this.alignment = alignment;
      }
      return Future<void>.value();
    }

    final key = handle ?? identityHashCode(this);
    _windowAnimationSessions.remove(key)?.cancel();
    final resolvedSize = size ?? this.size;
    final resolvedPosition =
        position ?? _resolveAlignedPosition(this, resolvedSize, alignment);

    final session = _WindowAnimationSession(
      window: this,
      targetSize: size,
      targetPosition: resolvedPosition,
      targetAlignment: alignment,
      duration: duration,
      curve: curve,
      onComplete: () => _windowAnimationSessions.remove(key),
    );

    _windowAnimationSessions[key] = session;
    return session.start();
  }

  Future<void> animateSize(
    Size size, {
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
  }) {
    return animateTo(size: size, duration: duration, curve: curve);
  }

  Future<void> animatePosition(
    Offset position, {
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
  }) {
    return animateTo(position: position, duration: duration, curve: curve);
  }
}

Offset? _resolveAlignedPosition(
  DesktopWindow window,
  Size targetSize,
  Alignment? alignment,
) {
  if (alignment == null) {
    return null;
  }
  final targetRect = getRectOnScreen(
    targetSize,
    alignment,
    window.workingScreenRect,
  );
  return targetRect.topLeft;
}

class _WindowAnimationSession {
  _WindowAnimationSession({
    required this.window,
    required this.targetSize,
    required this.targetPosition,
    required this.targetAlignment,
    required this.duration,
    required this.curve,
    required this.onComplete,
  });

  final DesktopWindow window;
  final Size? targetSize;
  final Offset? targetPosition;
  final Alignment? targetAlignment;
  final Duration duration;
  final Curve curve;
  final VoidCallback onComplete;

  final Completer<void> _completer = Completer<void>();
  Timer? _timer;
  late final DateTime _startedAt;
  late final double _coordinateScale;
  late final Size _initialSize;
  late final Offset _initialPosition;

  Future<void> start() {
    _startedAt = DateTime.now();
    _coordinateScale = _resolveCoordinateScale(window);
    _initialPosition = _getLogicalPosition(window, _coordinateScale);
    _initialSize = window.size;

    _applyFrame(0);
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final elapsed = DateTime.now().difference(_startedAt);
      final rawProgress = elapsed.inMicroseconds / duration.inMicroseconds;
      if (rawProgress >= 1) {
        _complete();
        return;
      }
      _applyFrame(rawProgress);
    });

    return _completer.future;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    onComplete();
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void _complete() {
    _timer?.cancel();
    _timer = null;
    _applyFrame(1);
    if (targetAlignment != null) {
      window.alignment = targetAlignment;
    }
    onComplete();
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void _applyFrame(double rawProgress) {
    final easedProgress = curve.transform(rawProgress.clamp(0.0, 1.0));
    final nextSize =
        Size.lerp(_initialSize, targetSize ?? _initialSize, easedProgress)!;
    final nextPosition = Offset.lerp(
      _initialPosition,
      targetPosition ?? _initialPosition,
      easedProgress,
    )!;

    if (targetSize != null || targetPosition != null) {
      window.rect = Rect.fromLTWH(
        nextPosition.dx * _coordinateScale,
        nextPosition.dy * _coordinateScale,
        nextSize.width * _coordinateScale,
        nextSize.height * _coordinateScale,
      );
    }
  }
}

double _resolveCoordinateScale(DesktopWindow window) {
  final logicalWidth = window.size.width;
  final physicalWidth = window.rect.width;
  if (logicalWidth <= 0 || physicalWidth <= 0) {
    return 1;
  }

  final inferredScale = physicalWidth / logicalWidth;
  if ((inferredScale - 1).abs() < 0.01) {
    return 1;
  }

  if (window.scaleFactor > 0 &&
      (inferredScale - window.scaleFactor).abs() < 0.05) {
    return window.scaleFactor;
  }

  return inferredScale;
}

Offset _getLogicalPosition(DesktopWindow window, double coordinateScale) {
  final position = window.position;
  if (coordinateScale == 0 || coordinateScale == 1) {
    return position;
  }
  return Offset(position.dx / coordinateScale, position.dy / coordinateScale);
}
