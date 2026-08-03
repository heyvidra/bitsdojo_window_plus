---
name: bitsdojo-window-plus
description: Use when integrating, customizing, or debugging the bitsdojo_window_plus Flutter desktop windowing library (Windows / macOS / Linux). Covers Dart-side API (runBitsdojoWindowApp, RoutedWindowHost, WindowConfiguration, appWindow, animateTo, multi-window routes) and the required native runner glue for each platform. Trigger on mentions of `bitsdojo_window`, `appWindow`, `WindowConfiguration`, `WindowBorder`, `WindowButtons`, `openNewWindow`, custom window frame, hide-on-startup, backgroundEffect, alwaysOnTop, titleBarHeight, multi-window Flutter desktop, or runner files like `main.cpp` / `MainFlutterWindow.swift` / `my_application.cc` that touch window setup.
---

# bitsdojo_window_plus

This repository **is** the library `bitsdojo_window_plus` — a federated Flutter plugin for customizing desktop windows on Windows, macOS, and Linux. Use this skill any time the user is consuming the library from another Flutter app, modifying its public Dart API, or touching the native runner glue that the library depends on.

Key value over upstream `bitsdojo_window`: built-in **multi-window** support, `backgroundEffect`, `alwaysOnTop`, `onClose` interceptor, per-button title-bar visibility, custom `titleBarHeight`, and a high-level `runBitsdojoWindowApp` + `RoutedWindowHost` setup that replaces the old manual `doWhenWindowReady` boilerplate.

## Package layout

Federated plugin. When debugging cross-cutting issues, remember which package owns the code:

- `bitsdojo_window/` — public Dart API consumers depend on.
- `bitsdojo_window_platform_interface/` — abstract `DesktopWindow`, `WindowEffect`, `DesktopWindowButton`, capability flags.
- `bitsdojo_window_windows/`, `bitsdojo_window_macos/`, `bitsdojo_window_linux/` — platform implementations + native runner-side headers (`bitsdojo_window_plugin.h`, `multi_window_manager.h`, `BitsdojoWindow.swift`, `BitsdojoWindowAppDelegate`, etc.).
- `example/` and `bitsdojo_window/example/` — reference apps showing real wiring.

Always grep across **all** these packages when tracing a feature; the Dart facade is thin and most behavior lives in the platform package.

## The Dart entry point — prefer the high-level API

For new code, **always recommend `runBitsdojoWindowApp`** over the legacy `doWhenWindowReady` + `runApp` pair. It handles binding init, route registration, window-ready callbacks, and `runApp` in one call.

```dart
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';

void main(List<String> args) {
  runBitsdojoWindowApp(
    app: const MyApp(),
    // Forward main's args: secondary windows receive their name/arguments as
    // `--bdw-name=` / `--bdw-args=` entrypoint arguments, making window.name
    // available before the first build (no windowReady race).
    args: args,
    routes: {
      'child': (context, arguments) => ChildScreen(arguments: arguments),
    },
    onWindowReady: (window) {
      if (window.isMainWindow) {
        window.size = const Size(900, 700);
        window.alignment = Alignment.center;
      }
      window.titleBarHeight = 50;
      window.show();
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: RoutedWindowHost(
          defaultChild: const MainScreen(),
          onCloseRequested: (context, window) async {
            if (!window.isMainWindow) return true; // child windows just close
            return await showDialog<bool>(
                  context: context,
                  builder: (_) => const ExitDialog(),
                ) ??
                false;
          },
        ),
      );
}
```

Lower-level escape hatches still exist and are valid when needed: `setupBitsdojoWindow(...)`, `doWhenWindowReady(...)`, `WindowRouter.register(...)`, and direct `appWindow.onClose = ...`. Use them only when `runBitsdojoWindowApp` doesn't fit (e.g., custom binding, tests).

## `RoutedWindowHost` — wraps your MaterialApp body

This widget does two jobs:
1. Picks the right widget for the current window via `WindowRouter` (uses `window.name`).
2. Wires `appWindow.onClose` and `appWindow.onArgumentsChanged` for the lifetime of the widget.

The `onCloseRequested` callback returns `Future<bool>`. **Return `true` to actually close, `false` to veto.** A common pattern: only intercept on the main window, let child windows close immediately.

## `WindowConfiguration` — declarative per-window setup

When the app has several windows (main + child routes), prefer registering `WindowConfiguration`s over hand-coding `onWindowReady` branches:

```dart
runBitsdojoWindowApp(
  app: const MyApp(),
  routes: { 'editor': (ctx, args) => EditorScreen(args: args) },
  windowConfigurations: [
    WindowConfiguration(
      mainWindow: true,
      size: const Size(1100, 720),
      minSize: const Size(800, 560),
      alignment: Alignment.center,
      titleBarHeight: 44,
      backgroundEffect: WindowEffect.acrylic, // Windows/macOS only
      readyAnimation: const WindowReadyAnimation.popIn(),
      onCloseRequested: (ctx, w) async => await confirmExit(ctx),
    ),
    WindowConfiguration(
      name: 'editor',
      size: const Size(720, 480),
      minSize: const Size(480, 320),
      alignment: Alignment.center,
      showOnReady: true,
    ),
  ],
);
```

Matching order: `mainWindow` flag, then `name`, then optional `matches` predicate. The first matching config wins, so put the most specific configs first. Each `WindowConfiguration` field also has a `*Builder` async variant (e.g., `sizeBuilder`) for values that need to be computed per-window at ready time.

## Multi-window — spawning children

```dart
await appWindow.openNewWindow(
  name: 'editor',
  size: const Size(720, 480),
  arguments: {'docId': 42},
);
```

In the child window the matching route from `routes:` receives `arguments`. `window.name` and `window.arguments` are also readable inside the child for branching. `window.isMainWindow` distinguishes the primary.

## `appWindow` — the global handle

`appWindow` is a `DesktopWindow`. Key surface you should be confident reaching for:

- Size / position: `size`, `minSize`, `maxSize`, `position`, `rect`, `alignment`.
- Visibility / state: `show()`, `hide()`, `close()`, `minimize()`, `maximize()`, `maximizeOrRestore()`, `restore()`, `toggleFullScreen()`, `isVisible`, `isMaximized`.
- Chrome: `title`, `titleBarHeight`, `titleBarButtonSize`, `setWindowTitleBarButtonVisibility(button, visible)`, `setWindowTitleBarButtonOffset(button, offset)`.
- Effects / behavior: `backgroundEffect = WindowEffect.acrylic|mica|tabbed|transparent|disabled`, `alwaysOnTop`, `hasShadow`.
- Drag: `startDragging()` — call from `onPanStart`/`MoveWindow` widget for custom title bars.
- Lifecycle: `onClose`, `onArgumentsChanged` (prefer wiring these via `RoutedWindowHost` / `WindowConfiguration`).
- Multi-window: `name`, `arguments`, `isMainWindow`, `depth`, `openNewWindow(...)`, `getWindowForHandle(handle)`, `terminateApp()`.
- Capabilities: `appWindow.capabilities.supportsBackgroundEffects` / `supportsTitleBarButtonVisibility` / `supportsTitleBarButtonOffset` — **check these before calling platform-gated APIs** to keep code cross-platform.

## Animated resize / move

`DesktopWindowAnimation` extension adds:

```dart
await appWindow.animateTo(
  size: const Size(900, 700),
  alignment: Alignment.center, // OR position: Offset(...), not both
  duration: const Duration(milliseconds: 280),
  curve: Curves.easeOutCubic,
);
// Convenience: animateSize(...), animatePosition(...)
```

Asserts trip if both `position` and `alignment` are given. A new `animateTo` cancels any in-flight animation for the same window. Internally it handles physical/logical pixel scaling, so always pass logical units.

Combine with `WindowReadyAnimation.popIn()` on `WindowConfiguration.readyAnimation` for a startup pop-in.

## Title-bar widgets

For a custom frame (`BDW_CUSTOM_FRAME`), build your own title bar with the provided widgets:

- `WindowBorder({color, width, child})` — wraps your scaffold with a 1px draggable border.
- `MoveWindow({child})` — invisible drag region; place behind your title content.
- `WindowButtons()` plus `MinimizeWindowButton`, `MaximizeWindowButton`, `CloseWindowButton` — pre-styled buttons. Customize via `WindowButtonColors`.
- `WindowTitleBarBox({child})` — sized to `appWindow.titleBarHeight`.

If `BDW_CUSTOM_FRAME` is **not** set, the OS chrome is shown and these widgets are unnecessary; only `appWindow` controls (size/effects/etc.) apply.

## Platform feature matrix — be honest about gaps

| Feature                              | Windows | macOS | Linux |
| ------------------------------------ | :-----: | :---: | :---: |
| Multi-window (`openNewWindow`)       |    Y    |   Y   |   Y   |
| `backgroundEffect`                   |    Y    |   Y   |   —   |
| `alwaysOnTop`                        |    Y    |   Y   |   Y   |
| `onClose` interceptor                |    Y    |   Y   |   Y   |
| `setWindowTitleBarButtonVisibility`  |    —    |   Y   |   Y   |
| `titleBarHeight`                     |    Y    |   Y   |   —   |

Always guard the unsupported calls behind `Platform.isX` or `appWindow.capabilities.*` rather than letting them silently no-op.

## Required native runner glue

These are **not optional** — without them the plugin can't take over the window or spawn children. When the user hits "size doesn't apply", "child window doesn't open", "buttons missing", inspect their runner files first.

### Windows — `windows/runner/main.cpp` + `flutter_window.cpp`

```cpp
// main.cpp
#include <bitsdojo_window_windows/bitsdojo_window_plugin.h>
#include <bitsdojo_window_windows/multi_window_manager.h>

auto bdw = bitsdojo_window_configure(BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP);

int APIENTRY wWinMain(...) {
  MultiWindowManager::GetInstance().SetWindowFactory(
    [](const wchar_t *title, int x, int y, int width, int height,
       const char *name, const char *arguments) -> HWND {
      flutter::DartProject project(L"data");
      std::vector<std::string> entrypoint_args;
      if (name && name[0]) {
        entrypoint_args.push_back(std::string("--bdw-name=") + name);
      }
      if (arguments && arguments[0]) {
        entrypoint_args.push_back(std::string("--bdw-args=") + arguments);
      }
      project.set_dart_entrypoint_arguments(std::move(entrypoint_args));
      auto window = new FlutterWindow(project);
      Win32Window::Point origin(x, y);
      Win32Window::Size size(width, height);
      if (window->Create(title, origin, size)) return window->GetHandle();
      delete window;
      return nullptr;
    });
  // ... rest of standard runner
}
```

```cpp
// flutter_window.cpp
#include <bitsdojo_window_windows/multi_window_manager.h>

// In MessageHandler's switch, before delegating to Win32Window::MessageHandler.
// Do NOT call OnWindowDestroyed from OnDestroy(): the stock Win32Window
// template nulls window_handle_ before OnDestroy runs, so GetHandle()
// there returns nullptr and the cleanup silently no-ops.
case WM_DESTROY:
  MultiWindowManager::GetInstance().OnWindowDestroyed(hwnd);
  break;

// OnDestroy keeps its stock body (engine teardown):
void FlutterWindow::OnDestroy() {
  if (flutter_controller_) flutter_controller_ = nullptr;
  Win32Window::OnDestroy();
}
```

The runner-side `OnWindowDestroyed` call is best-effort: the plugin's own
`WM_NCDESTROY` subclass hook performs the same cleanup for every registered
window, so un-updated runners still get correct MultiWindowManager cleanup.

Note on `--bdw-*` args: secondary windows receive `--bdw-name=` / `--bdw-args=`
in `main(List<String> args)`. If the app parses main's args itself, filter them
first with `withoutWindowIdentityArgs(args)`. Launching the app manually with
`--bdw-*` on the command line would mis-seed the primary window — these flags
are reserved for windows spawned by the plugin.

Flags: `BDW_CUSTOM_FRAME` removes OS title bar; `BDW_HIDE_ON_STARTUP` hides until `window.show()`. Drop either flag to opt out.

### macOS — `AppDelegate.swift` + `MainFlutterWindow.swift`

```swift
// AppDelegate.swift
import Cocoa
import bitsdojo_window_macos

@main
class AppDelegate: BitsdojoWindowAppDelegate {}
```

```swift
// MainFlutterWindow.swift
import Cocoa
import FlutterMacOS
import bitsdojo_window_macos

class MainFlutterWindow: BitsdojoWindow {
  override func bitsdojo_window_configure() -> UInt {
    return BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP
  }
  override func bitsdojo_window_title_bar_height() -> Double { 50.0 }
  override func setupFlutter() {
    super.setupFlutter()
    if let vc = self.contentViewController as? FlutterViewController {
      RegisterGeneratedPlugins(registry: vc)
    }
    // Safety net for windows created with a class that doesn't register
    // plugins itself (MultiWindowManager calls it only when needed).
    MultiWindowManager.shared.pluginRegistrant = { registry in
      RegisterGeneratedPlugins(registry: registry)
    }
  }
}
```

`BitsdojoWindowAppDelegate` already handles the main-window close lifecycle for multi-window apps — do **not** re-hand-roll `applicationShouldTerminateAfterLastWindowClosed` etc.

### Linux — `linux/my_application.cc`

```c
#include <bitsdojo_window_linux/bitsdojo_window_plugin.h>

auto bdw = bitsdojo_window_from(window);
bdw->setCustomFrame(true);
bitsdojo_window_set_dart_entrypoint_arguments(self->dart_entrypoint_arguments);
bitsdojo_window_configure_from_environment(window);
```

Linux startup tips that bite people:
- Keep the GTK window **hidden** until Flutter's `first-frame` signal, then `gtk_widget_show` + `gtk_window_present`.
- Only `gtk_window_present` immediately from `command_line` for an already-existing window. A brand-new child window should wait for first frame.
- Give `FlView` a light background, not pure black — Flutter scaffolds may be transparent.

`bitsdojo_window_configure_from_environment` restores child-window state from env vars set by the parent process; without it child windows open with wrong size/position.

## Adding the dependency

This package is published from a git repo, not pub.dev. Pin a ref:

```yaml
dependencies:
  bitsdojo_window:
    git:
      url: https://github.com/Twilight-Evd/bitsdojo_window_plus.git
      path: bitsdojo_window
      ref: v0.0.1
```

Federated subpackages (`bitsdojo_window_macos`, etc.) are pulled in transitively — consumers don't add them manually.

## Common pitfalls (check these first when debugging)

1. **"Window flashes at the wrong size on startup"** — the consumer forgot `BDW_HIDE_ON_STARTUP` or is calling `window.show()` before applying size. Fix: keep the flag, set size in `onWindowReady` / `WindowConfiguration`, then `show()`.
2. **"Child window opens but routes don't match"** — `routes:` key must equal the `name:` passed to `openNewWindow(...)`. Names are case-sensitive.
3. **"`backgroundEffect` does nothing on Linux"** — unsupported; gate with `Platform.isLinux` or capabilities. Same for `titleBarHeight` on Linux.
4. **"`onClose` fires but window won't actually close"** — the interceptor returned `false` (or threw). The library only calls `appWindow.close()` when the interceptor resolves to `true`. If you set `appWindow.onClose` manually *and* mount `RoutedWindowHost`, the host overwrites it — pick one.
5. **"Drag doesn't work on the custom title bar"** — wrap the title region with `MoveWindow` (or call `appWindow.startDragging()` from a `GestureDetector.onPanStart`). Buttons should sit on top of `MoveWindow`, not inside it.
6. **"Multi-window broken on Windows"** — `MultiWindowManager::SetWindowFactory` not wired in `main.cpp`. (The `OnWindowDestroyed` runner call is best-effort since the plugin's `WM_NCDESTROY` hook took over cleanup; the factory is still mandatory.)
7. **"macOS app quits when last child window closes unexpectedly"** — the app delegate isn't extending `BitsdojoWindowAppDelegate`. Don't subclass `FlutterAppDelegate` directly.
8. **Editing tests** — there are test fakes/mocks for `DesktopWindow` (see `bitsdojo_window_platform_interface/test/`). When adding a new field to `DesktopWindow`, update the fakes too; CI has previously broken on missing `hasShadow` impls (see commit `10afe0c`).

## When changing the library itself

- Public Dart surface is re-exported from `bitsdojo_window/lib/bitsdojo_window.dart`. New exports go there.
- New `DesktopWindow` members must be added to the abstract class in `bitsdojo_window_platform_interface/lib/window.dart` **and** implemented in all three platform packages **and** updated in test fakes.
- Capability flags belong on `DesktopWindowCapabilities`; gate per-platform in `platformWindowCapabilities` inside `bitsdojo_window/lib/src/app_window.dart`.
- The example apps under `example/` and `bitsdojo_window/example/` are the integration smoke test — run them on the target platform before claiming a change works.

## Quick reference — what to read in this repo

| Question                                   | File                                                              |
| ------------------------------------------ | ----------------------------------------------------------------- |
| Public Dart exports                        | `bitsdojo_window/lib/bitsdojo_window.dart`                        |
| `runBitsdojoWindowApp`, `RoutedWindowHost` | `bitsdojo_window/lib/src/window_integration.dart`                 |
| `WindowConfiguration`, `popIn` animation   | `bitsdojo_window/lib/src/window_configuration.dart`               |
| `appWindow`, platform routing              | `bitsdojo_window/lib/src/app_window.dart`                         |
| `animateTo` / size+position animation      | `bitsdojo_window/lib/src/window_animation.dart`                   |
| Multi-window routing                       | `bitsdojo_window/lib/src/window_router.dart`                      |
| Abstract `DesktopWindow`, `WindowEffect`   | `bitsdojo_window_platform_interface/lib/window.dart`              |
| macOS native side                          | `bitsdojo_window_macos/macos/.../BitsdojoWindow.swift`            |
| Windows native side                        | `bitsdojo_window_windows/windows/.../bitsdojo_window_plugin.cpp`  |
| Linux native side                          | `bitsdojo_window_linux/linux/.../bitsdojo_window_plugin.cc`       |
