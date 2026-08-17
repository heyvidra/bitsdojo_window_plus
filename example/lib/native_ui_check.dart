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
      window.size = const Size(700, 500);
      window.alignment = Alignment.center;
      window.show();

      await Future.delayed(const Duration(seconds: 3));
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
