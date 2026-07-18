# bitsdojo_window

A [Flutter package](https://pub.dev/packages/bitsdojo_window) that makes it easy to customize and work with your Flutter desktop app window **on Windows, macOS and Linux**. 

Watch the tutorial to get started. Click the image below to watch the video: 

[![IMAGE ALT TEXT](https://img.youtube.com/vi/bee2AHQpGK4/0.jpg)](https://www.youtube.com/watch?v=bee2AHQpGK4 "Click to open")

<img src="https://raw.githubusercontent.com/bitsdojo/bitsdojo_window/master/resources/screenshot.png">

**Features**:

    - Custom window frame - remove standard Windows/macOS/Linux titlebar and buttons
    - Hide window on startup
    - Show/hide window
    - Move window using Flutter widget
    - Minimize/Maximize/Restore/Close window
    - Set window size, minimum size and maximum size
    - Set window position
    - Set window alignment on screen (center/topLeft/topRight/bottomLeft/bottomRight)
    - Set window title

# Getting Started

Install the package using `pubspec.yaml`

# For Windows apps

Inside your application folder, go to `windows\runner\main.cpp` and add the plugin glue for custom frame support:

```cpp
#include <bitsdojo_window_windows/bitsdojo_window_plugin.h>
auto bdw = bitsdojo_window_configure(BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP);
```

For multi-window apps, also include the window manager and register a factory before creating the main `FlutterWindow`:

```cpp
#include <bitsdojo_window_windows/multi_window_manager.h>

MultiWindowManager::GetInstance().SetWindowFactory(
    [](const wchar_t *title, int x, int y, int width, int height,
       const char *name, const char *arguments) -> HWND {
      flutter::DartProject project(L"data");
      auto window = new FlutterWindow(project);
      Win32Window::Point origin(x, y);
      Win32Window::Size size(width, height);

      if (window->Create(title, origin, size)) {
        return window->GetHandle();
      }

      delete window;
      return nullptr;
    });
```

And in `windows\runner\flutter_window.cpp`, clean up the plugin's native state when a window is destroyed:

```cpp
#include <bitsdojo_window_windows/multi_window_manager.h>

void FlutterWindow::OnDestroy() {
  MultiWindowManager::GetInstance().OnWindowDestroyed(GetHandle());
  ...
}
```

# For macOS apps

Inside your application folder, go to `macos\runner\AppDelegate.swift` and use the plugin base delegate:

```swift
import Cocoa
import bitsdojo_window_macos

@main
class AppDelegate: BitsdojoWindowAppDelegate {}
```

Then update `macos\runner\MainFlutterWindow.swift` to use `BitsdojoWindow`:

```swift
import FlutterMacOS
import bitsdojo_window_macos
```

```swift
class MainFlutterWindow: BitsdojoWindow {
  override func bitsdojo_window_configure() -> UInt {
    return BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP
  }

  override func setupFlutter() {
    super.setupFlutter()
    if let flutterViewController = self.contentViewController as? FlutterViewController {
      RegisterGeneratedPlugins(registry: flutterViewController)
    }
  }
}
```

If you want a taller draggable title bar region, you can also override:

```swift
override func bitsdojo_window_title_bar_height() -> Double {
  return 50.0
}
```

This is the minimum macOS runner setup for custom frames, plugin-managed close handling, and multi-window support.
#

If you don't want to use a custom frame and prefer the standard window titlebar and buttons, you can remove the `BDW_CUSTOM_FRAME` flag from the code above.

If you don't want to hide the window on startup, you can remove the `BDW_HIDE_ON_STARTUP` flag from the code above.

# For Linux apps

Inside your application folder, go to `linux\my_application.cc` and add this line at the beginning of the file:

```cpp
#include <bitsdojo_window_linux/bitsdojo_window_plugin.h>
```
For multi-window apps, also keep the Dart entrypoint arguments in your application struct:

```cpp
struct _MyApplication {
  GtkApplication parent_instance;
  char **dart_entrypoint_arguments;
};
```

Then update the runner setup to this:

```cpp
auto bdw = bitsdojo_window_from(window);
bdw->setCustomFrame(true);
bitsdojo_window_set_dart_entrypoint_arguments(self->dart_entrypoint_arguments);
bitsdojo_window_configure_from_environment(window);
```

Before creating the `FlView`, restore the saved arguments:

```cpp
if (self->dart_entrypoint_arguments) {
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);
}
```

When creating the `FlView`, it is a good idea to set a non-black fallback background if your Flutter UI draws transparent surfaces:

```cpp
FlView *view = fl_view_new(project);
GdkRGBA background_color;
gdk_rgba_parse(&background_color, "#F6FBFA");
fl_view_set_background_color(view, &background_color);
```

And implement `local_command_line` so each launched window keeps its own arguments:

```cpp
extern "C" gboolean my_application_local_command_line(
    GApplication *application,
    gchar ***arguments,
    int *exit_status) {
  MyApplication *self = MY_APPLICATION(application);

  if (self->dart_entrypoint_arguments) {
    g_strfreev(self->dart_entrypoint_arguments);
  }
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  return FALSE;
}
```

For the smoothest Linux multi-window startup:
- Keep the top-level window hidden until the Flutter `first-frame` signal fires, then show/present it.
- In `command_line`, only call `gtk_window_present(...)` immediately when you are targeting an already-existing window. Let brand-new child windows wait for their first frame.

# Flutter app integration

For new integrations, the shortest Flutter-side setup is:

```dart
void main() {
  runBitsdojoWindowApp(
    app: const MyApp(),
    onWindowReady: (window) {
      const initialSize = Size(600, 450);
      window.minSize = initialSize;
      window.size = initialSize;
      window.alignment = Alignment.center;
      window.show();
    },
  );
}
```

This sets an initial size and a minimum size for your application window, centers it on screen, and shows it after the first frame is ready.

If you prefer lower-level control, `doWhenWindowReady(...)`, `WindowRouter`, and `appWindow.onClose` are still available.

For animated resize/reposition flows, prefer semantic alignment when possible:

```dart
await appWindow.animateTo(
  size: const Size(900, 700),
  alignment: Alignment.center,
  duration: const Duration(milliseconds: 280),
);
```

You can find examples in the `example` folder.

Here is an example that displays this window:
<details>
<summary>Click to expand</summary>

```dart
import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';

void main() {
  runBitsdojoWindowApp(
    app: const MyApp(),
    onWindowReady: (window) {
      const initialSize = Size(600, 450);
      window.minSize = initialSize;
      window.size = initialSize;
      window.alignment = Alignment.center;
      window.title = "Custom window with Flutter";
      window.show();
    },
  );
}

const borderColor = Color(0xFF805306);

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: WindowBorder(
          color: borderColor,
          width: 1,
          child: Row(
            children: const [LeftSide(), RightSide()],
          ),
        ),
      ),
    );
  }
}

const sidebarColor = Color(0xFFF6A00C);

class LeftSide extends StatelessWidget {
  const LeftSide({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: 200,
        child: Container(
            color: sidebarColor,
            child: Column(
              children: [
                WindowTitleBarBox(child: MoveWindow()),
                Expanded(child: Container())
              ],
            )));
  }
}

const backgroundStartColor = Color(0xFFFFD500);
const backgroundEndColor = Color(0xFFF6A00C);

class RightSide extends StatelessWidget {
  const RightSide({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [backgroundStartColor, backgroundEndColor],
              stops: [0.0, 1.0]),
        ),
        child: Column(children: [
          WindowTitleBarBox(
            child: Row(
              children: [Expanded(child: MoveWindow()), const WindowButtons()],
            ),
          )
        ]),
      ),
    );
  }
}

final buttonColors = WindowButtonColors(
    iconNormal: const Color(0xFF805306),
    mouseOver: const Color(0xFFF6A00C),
    mouseDown: const Color(0xFF805306),
    iconMouseOver: const Color(0xFF805306),
    iconMouseDown: const Color(0xFFFFD500));

final closeButtonColors = WindowButtonColors(
    mouseOver: const Color(0xFFD32F2F),
    mouseDown: const Color(0xFFB71C1C),
    iconNormal: const Color(0xFF805306),
    iconMouseOver: Colors.white);

class WindowButtons extends StatelessWidget {
  const WindowButtons({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MinimizeWindowButton(colors: buttonColors),
        MaximizeWindowButton(colors: buttonColors),
        CloseWindowButton(colors: closeButtonColors),
      ],
    );
  }
}
```
</details>

#
# ❤️ **Sponsors - friends helping this package**

I am developing this package in my spare time and any help is appreciated. 
If you want to help you can [become a sponsor](https://github.com/sponsors/bitsdojo).

🙏 Thank you!

Want to help? [Become a sponsor](https://github.com/sponsors/bitsdojo)
