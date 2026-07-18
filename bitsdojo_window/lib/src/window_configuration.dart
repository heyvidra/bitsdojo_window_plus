import 'dart:async';

import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:flutter/widgets.dart';

import 'window_animation.dart';

typedef WindowValueResolver<T> = FutureOr<T?> Function(DesktopWindow window);
typedef WindowPredicate = bool Function(DesktopWindow window);
typedef WindowCloseInterceptor = FutureOr<bool> Function(
  BuildContext context,
  DesktopWindow window,
);
typedef WindowArgumentsHandler = void Function(DesktopWindow window);
typedef WindowLifecycleHook = FutureOr<void> Function(DesktopWindow window);

class WindowReadyAnimation {
  const WindowReadyAnimation.none()
    : duration = Duration.zero,
      startScale = 1,
      minimumSize = Size.zero,
      positionOffset = Offset.zero;

  const WindowReadyAnimation.popIn({
    this.duration = const Duration(milliseconds: 260),
    this.startScale = 0.92,
    this.minimumSize = const Size(320, 220),
    this.positionOffset = const Offset(0, 18),
  });

  final Duration duration;
  final double startScale;
  final Size minimumSize;
  final Offset positionOffset;

  bool get enabled => duration > Duration.zero && startScale > 0;

  Future<void> apply(DesktopWindow window) async {
    if (!enabled) return;

    final targetSize = window.size;
    final targetPosition = window.position;
    if (targetSize.width <= 0 || targetSize.height <= 0) {
      return;
    }

    final startSize = Size(
      (targetSize.width * startScale)
          .clamp(minimumSize.width, targetSize.width)
          .toDouble(),
      (targetSize.height * startScale)
          .clamp(minimumSize.height, targetSize.height)
          .toDouble(),
    );
    final widthDelta = targetSize.width - startSize.width;
    final heightDelta = targetSize.height - startSize.height;
    final startPosition = Offset(
      targetPosition.dx + (widthDelta / 2) + positionOffset.dx,
      targetPosition.dy + (heightDelta / 2) + positionOffset.dy,
    );

    window.size = startSize;
    window.position = startPosition;

    unawaited(
      window.animateTo(
        size: targetSize,
        position: targetPosition,
        duration: duration,
      ),
    );
  }
}

class WindowConfiguration {
  const WindowConfiguration({
    this.name,
    this.mainWindow,
    this.matches,
    this.title,
    this.titleBuilder,
    this.size,
    this.sizeBuilder,
    this.minSize,
    this.minSizeBuilder,
    this.maxSize,
    this.maxSizeBuilder,
    this.alignment,
    this.alignmentBuilder,
    this.titleBarHeight,
    this.titleBarHeightBuilder,
    this.backgroundEffect,
    this.backgroundEffectBuilder,
    this.alwaysOnTop,
    this.alwaysOnTopBuilder,
    this.hasShadow,
    this.hasShadowBuilder,
    this.buttonVisibility = const {},
    this.buttonVisibilityBuilder,
    this.showOnReady = true,
    this.readyAnimation = const WindowReadyAnimation.none(),
    this.beforeApply,
    this.afterApply,
    this.onCloseRequested,
    this.onArgumentsChanged,
  });

  final String? name;
  final bool? mainWindow;
  final WindowPredicate? matches;

  final String? title;
  final WindowValueResolver<String>? titleBuilder;
  final Size? size;
  final WindowValueResolver<Size>? sizeBuilder;
  final Size? minSize;
  final WindowValueResolver<Size>? minSizeBuilder;
  final Size? maxSize;
  final WindowValueResolver<Size>? maxSizeBuilder;
  final Alignment? alignment;
  final WindowValueResolver<Alignment>? alignmentBuilder;
  final double? titleBarHeight;
  final WindowValueResolver<double>? titleBarHeightBuilder;
  final WindowEffect? backgroundEffect;
  final WindowValueResolver<WindowEffect>? backgroundEffectBuilder;
  final bool? alwaysOnTop;
  final WindowValueResolver<bool>? alwaysOnTopBuilder;
  final bool? hasShadow;
  final WindowValueResolver<bool>? hasShadowBuilder;
  final Map<DesktopWindowButton, bool> buttonVisibility;
  final WindowValueResolver<Map<DesktopWindowButton, bool>>?
  buttonVisibilityBuilder;
  final bool showOnReady;
  final WindowReadyAnimation readyAnimation;
  final WindowLifecycleHook? beforeApply;
  final WindowLifecycleHook? afterApply;
  final WindowCloseInterceptor? onCloseRequested;
  final WindowArgumentsHandler? onArgumentsChanged;

  bool matchesWindow(DesktopWindow window) {
    if (mainWindow != null && window.isMainWindow != mainWindow) {
      return false;
    }
    if (name != null && window.name != name) {
      return false;
    }
    return matches?.call(window) ?? true;
  }

  Future<void> applyTo(DesktopWindow window) async {
    await beforeApply?.call(window);

    final resolvedTitle = await _resolve(titleBuilder, title, window);
    if (resolvedTitle != null) {
      window.title = resolvedTitle;
    }

    final resolvedSize = await _resolve(sizeBuilder, size, window);
    if (resolvedSize != null) {
      window.size = resolvedSize;
    }

    final resolvedMinSize = await _resolve(minSizeBuilder, minSize, window);
    window.minSize = resolvedMinSize;

    final resolvedMaxSize = await _resolve(maxSizeBuilder, maxSize, window);
    window.maxSize = resolvedMaxSize;

    final resolvedAlignment = await _resolve(
      alignmentBuilder,
      alignment,
      window,
    );
    if (resolvedAlignment != null) {
      window.alignment = resolvedAlignment;
    }

    final resolvedTitleBarHeight = await _resolve(
      titleBarHeightBuilder,
      titleBarHeight,
      window,
    );
    if (resolvedTitleBarHeight != null) {
      window.titleBarHeight = resolvedTitleBarHeight;
    }

    final resolvedBackgroundEffect = await _resolve(
      backgroundEffectBuilder,
      backgroundEffect,
      window,
    );
    if (resolvedBackgroundEffect != null) {
      window.backgroundEffect = resolvedBackgroundEffect;
    }

    final resolvedAlwaysOnTop = await _resolve(
      alwaysOnTopBuilder,
      alwaysOnTop,
      window,
    );
    if (resolvedAlwaysOnTop != null) {
      window.alwaysOnTop = resolvedAlwaysOnTop;
    }

    final resolvedHasShadow = await _resolve(
      hasShadowBuilder,
      hasShadow,
      window,
    );
    if (resolvedHasShadow != null) {
      window.hasShadow = resolvedHasShadow;
    }

    final resolvedButtonVisibility = await _resolve(
      buttonVisibilityBuilder,
      buttonVisibility,
      window,
    );
    if (resolvedButtonVisibility != null) {
      for (final entry in resolvedButtonVisibility.entries) {
        window.setWindowTitleBarButtonVisibility(entry.key, entry.value);
      }
    }

    await readyAnimation.apply(window);

    if (showOnReady) {
      window.show();
    }

    await afterApply?.call(window);
  }

  static Future<T?> _resolve<T>(
    WindowValueResolver<T>? builder,
    T? value,
    DesktopWindow window,
  ) async {
    if (builder != null) {
      return await builder(window);
    }
    return value;
  }
}

class WindowConfigurationRegistry {
  WindowConfigurationRegistry._();

  static final List<WindowConfiguration> _configurations = [];

  static void registerAll(List<WindowConfiguration> configurations) {
    _configurations
      ..clear()
      ..addAll(configurations);
  }

  static void clear() {
    _configurations.clear();
  }

  static WindowConfiguration? resolve(DesktopWindow window) {
    for (final configuration in _configurations) {
      if (configuration.matchesWindow(window)) {
        return configuration;
      }
    }
    return null;
  }

  static Future<void> apply(DesktopWindow window) async {
    await resolve(window)?.applyTo(window);
  }
}
