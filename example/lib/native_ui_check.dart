// Temporary harness: exercises the native alert + menu once at startup, prints
// what came back, then exits — so a headless Linux/Windows run can verify the
// whole Dart -> channel -> GTK/Win32 -> Dart round trip without a human.
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';

void main(List<String> args) {
  runBitsdojoWindowApp(
    app: const MaterialApp(
      home: Scaffold(body: Center(child: Text('native ui check'))),
    ),
    args: args,
    onWindowReady: (window) async {
      final seen = <String>[];
      window.events.listen((event) {
        final label = switch (event) {
          WindowFocused() => 'focused',
          WindowBlurred() => 'blurred',
          WindowMoved(:final position) => 'moved(${position.dx},${position.dy})',
          WindowResized(:final size) => 'resized(${size.width}x${size.height})',
          WindowMinimized() => 'minimized',
          WindowMaximized() => 'maximized',
          WindowRestored() => 'restored',
        };
        seen.add(label);
        debugPrint('CHECK event $label');
      });

      window.size = const Size(700, 500);
      window.alignment = Alignment.center;
      window.show();

      await Future.delayed(const Duration(seconds: 2));
      final displays = await getDisplays();
      debugPrint('CHECK displays count=${displays.length}');
      for (final display in displays) {
        debugPrint('CHECK display $display');
      }

      // Drive a move and a resize, then report which events arrived.
      window.position = const Offset(120, 120);
      await Future.delayed(const Duration(milliseconds: 600));
      window.size = const Size(640, 460);
      await Future.delayed(const Duration(milliseconds: 600));
      debugPrint('CHECK events after move+resize: ${seen.join(",")}');

      // The animation writes a rect every frame through the shared scratch
      // struct, so it is the real test of that pooling: if a frame ever read a
      // half-written struct the window would land somewhere else.
      await appWindow.animateTo(
        size: const Size(560, 400),
        position: const Offset(200, 160),
        duration: const Duration(milliseconds: 300),
      );
      debugPrint('CHECK animated to size=${appWindow.size} '
          'position=${appWindow.position}');

      // bottomLeft used to land one full window width off the left edge, and an
      // unnamed Alignment collapsed the window to Rect.zero. Both should now
      // sit inside the work area.
      for (final alignment in const [Alignment.bottomLeft, Alignment(0, 0.5)]) {
        appWindow.alignment = alignment;
        await Future.delayed(const Duration(milliseconds: 400));
        final work = appWindow.workingScreenRect;
        final onScreen = appWindow.position.dx >= work.left - 1 &&
            appWindow.position.dy >= work.top - 1 &&
            appWindow.size.width > 0;
        debugPrint('CHECK align $alignment -> position=${appWindow.position} '
            'size=${appWindow.size} onScreen=$onScreen');
      }

      // Marker for the driver script: everything above is non-interactive, and
      // what follows needs a keypress. Waiting on this beats guessing a sleep,
      // which silently mistimes every time a step is added above.
      await Future.delayed(const Duration(seconds: 1));
      debugPrint('CHECK awaiting-alert');
      final index = await showNativeAlert(
        title: 'Round trip?',
        message: 'Press Return for the first button.',
        buttons: ['Yes', 'No'],
        style: NativeAlertStyle.warning,
      );
      debugPrint('CHECK alert index=$index');

      await Future.delayed(const Duration(seconds: 1));
      final picked = await showNativeMenu(
        const [
          NativeMenuItem('copy', 'Copy'),
          NativeMenuItem('paste', 'Paste', enabled: false),
          NativeMenuItem.separator(),
          NativeMenuItem('view', 'View', submenu: [
            NativeMenuItem('wrap', 'Wrap lines', checked: true),
          ]),
        ],
        position: const Offset(120, 120),
      );
      debugPrint('CHECK menu picked=$picked');

      // Smoke test for the fullscreen background-effect guard: this window sets
      // no backgroundEffect, which is exactly the case that used to be forced
      // opaque on every transition.
      await Future.delayed(const Duration(seconds: 1));
      window.toggleFullScreen();
      await Future.delayed(const Duration(seconds: 3));
      window.toggleFullScreen();
      await Future.delayed(const Duration(seconds: 3));
      debugPrint('CHECK fullscreen round trip survived, '
          'visible=${window.isVisible} size=${window.size}');

      debugPrint('CHECK done');
      exit(0);
    },
  );
}
