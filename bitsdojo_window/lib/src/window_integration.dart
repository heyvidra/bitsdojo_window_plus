import 'dart:async';

import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:flutter/widgets.dart';

import 'app_window.dart';
import 'window_configuration.dart';
import 'window_router.dart';

typedef WindowReadyHandler = void Function(DesktopWindow window);
typedef BitsdojoWindowAppBuilder = Widget Function();

void runBitsdojoWindowApp({
  required Widget app,
  Map<String, WindowBuilder> routes = const {},
  List<WindowConfiguration> windowConfigurations = const [],
  WindowReadyHandler? onWindowReady,
}) {
  WidgetsFlutterBinding.ensureInitialized();
  setupBitsdojoWindow(
    routes: routes,
    windowConfigurations: windowConfigurations,
    onWindowReady: onWindowReady,
  );
  runApp(app);
}

void setupBitsdojoWindow({
  Map<String, WindowBuilder> routes = const {},
  List<WindowConfiguration> windowConfigurations = const [],
  WindowReadyHandler? onWindowReady,
}) {
  WindowRouter.registerAll(routes);
  WindowConfigurationRegistry.registerAll(windowConfigurations);
  doWhenWindowReady(() async {
    await WindowConfigurationRegistry.apply(appWindow);
    onWindowReady?.call(appWindow);
  });
}

class RoutedWindowHost extends StatelessWidget {
  const RoutedWindowHost({
    super.key,
    required this.defaultChild,
    this.window,
    this.onCloseRequested,
    this.onArgumentsChanged,
    this.rebuildOnArgumentsChanged = true,
  });

  final Widget defaultChild;
  final DesktopWindow? window;
  final WindowCloseInterceptor? onCloseRequested;
  final WindowArgumentsHandler? onArgumentsChanged;
  final bool rebuildOnArgumentsChanged;

  @override
  Widget build(BuildContext context) {
    final activeWindow = window ?? appWindow;
    return WindowEventListener(
      onCloseRequested: onCloseRequested,
      onArgumentsChanged: onArgumentsChanged,
      rebuildOnArgumentsChanged: rebuildOnArgumentsChanged,
      child: WindowRouter.build(
        context,
        activeWindow,
        defaultWidget: defaultChild,
      ),
    );
  }
}

class WindowEventListener extends StatefulWidget {
  const WindowEventListener({
    super.key,
    required this.child,
    this.onCloseRequested,
    this.onArgumentsChanged,
    this.rebuildOnArgumentsChanged = true,
  });

  final Widget child;
  final WindowCloseInterceptor? onCloseRequested;
  final WindowArgumentsHandler? onArgumentsChanged;
  final bool rebuildOnArgumentsChanged;

  @override
  State<WindowEventListener> createState() => _WindowEventListenerState();
}

class _WindowEventListenerState extends State<WindowEventListener> {
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    appWindow.onClose = _handleCloseRequested;
    appWindow.onArgumentsChanged = _handleArgumentsChanged;
  }

  @override
  void dispose() {
    _disposed = true;
    appWindow.onClose = null;
    appWindow.onArgumentsChanged = null;
    super.dispose();
  }

  Future<void> _handleCloseRequested() async {
    final interceptor =
        widget.onCloseRequested ??
        WindowConfigurationRegistry.resolve(appWindow)?.onCloseRequested;
    if (interceptor == null) {
      appWindow.close();
      return;
    }

    final shouldClose = await interceptor(context, appWindow);
    if (!_disposed && shouldClose) {
      appWindow.close();
    }
  }

  void _handleArgumentsChanged() {
    widget.onArgumentsChanged?.call(appWindow);
    WindowConfigurationRegistry.resolve(appWindow)?.onArgumentsChanged?.call(
      appWindow,
    );
    if (!_disposed && widget.rebuildOnArgumentsChanged) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
