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
  List<String> args = const [],
  Map<String, WindowBuilder> routes = const {},
  List<WindowConfiguration> windowConfigurations = const [],
  WindowReadyHandler? onWindowReady,
}) {
  WidgetsFlutterBinding.ensureInitialized();
  setupBitsdojoWindow(
    args: args,
    routes: routes,
    windowConfigurations: windowConfigurations,
    onWindowReady: onWindowReady,
  );
  runApp(app);
}

void setupBitsdojoWindow({
  List<String> args = const [],
  Map<String, WindowBuilder> routes = const {},
  List<WindowConfiguration> windowConfigurations = const [],
  WindowReadyHandler? onWindowReady,
}) {
  seedWindowIdentityFromArgs(args);
  WindowRouter.registerAll(routes);
  WindowConfigurationRegistry.registerAll(windowConfigurations);
  doWhenWindowReady(() async {
    await WindowConfigurationRegistry.apply(appWindow);
    onWindowReady?.call(appWindow);
  });
}

class RoutedWindowHost extends StatefulWidget {
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
  State<RoutedWindowHost> createState() => _RoutedWindowHostState();
}

class _RoutedWindowHostState extends State<RoutedWindowHost> {
  DesktopWindow get _activeWindow => widget.window ?? appWindow;

  @override
  void initState() {
    super.initState();
    _activeWindow.changes.addListener(_onWindowChanged);
  }

  @override
  void didUpdateWidget(RoutedWindowHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.window != widget.window) {
      (oldWidget.window ?? appWindow).changes.removeListener(_onWindowChanged);
      _activeWindow.changes.addListener(_onWindowChanged);
    }
  }

  @override
  void dispose() {
    _activeWindow.changes.removeListener(_onWindowChanged);
    super.dispose();
  }

  void _onWindowChanged() {
    // Re-evaluate the route here, in the State that owns the setState:
    // window.name/arguments may only arrive via the native windowReady
    // message after the first build (the entrypoint-args fast path makes
    // them available earlier, but un-updated runners rely on this).
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return WindowEventListener(
      onCloseRequested: widget.onCloseRequested,
      onArgumentsChanged: widget.onArgumentsChanged,
      rebuildOnArgumentsChanged: widget.rebuildOnArgumentsChanged,
      child: WindowRouter.build(
        context,
        _activeWindow,
        defaultWidget: widget.defaultChild,
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
  @override
  void initState() {
    super.initState();
    assert(() {
      if (appWindow.onClose != null || appWindow.onArgumentsChanged != null) {
        debugPrint(
          'bitsdojo_window: WindowEventListener is replacing an existing '
          'onClose/onArgumentsChanged handler. These are single-slot '
          'callbacks — mount only one listener (or use window.changes for '
          'multi-listener notifications).',
        );
      }
      return true;
    }());
    appWindow.onClose = _handleCloseRequested;
    appWindow.onArgumentsChanged = _handleArgumentsChanged;
  }

  @override
  void dispose() {
    // Only release the slots this listener still owns — a newer listener
    // (e.g. two hosts briefly mounted during a route transition) may have
    // replaced them, and nulling unconditionally would silently disable it.
    if (appWindow.onClose == _handleCloseRequested) {
      appWindow.onClose = null;
    }
    if (appWindow.onArgumentsChanged == _handleArgumentsChanged) {
      appWindow.onArgumentsChanged = null;
    }
    super.dispose();
  }

  Future<void> _handleCloseRequested() async {
    final interceptor =
        widget.onCloseRequested ??
        WindowConfigurationRegistry.resolve(appWindow)?.onCloseRequested;
    // A defunct listener can't safely hand its BuildContext to the
    // interceptor (e.g. showDialog) — fall through to a plain close.
    if (interceptor == null || !mounted) {
      appWindow.close();
      return;
    }

    final shouldClose = await interceptor(context, appWindow);
    // `mounted` only guards BuildContext use, which already happened —
    // a close the user explicitly confirmed must not be dropped just
    // because this listener unmounted during the await.
    if (shouldClose) {
      appWindow.close();
    }
  }

  void _handleArgumentsChanged() {
    widget.onArgumentsChanged?.call(appWindow);
    WindowConfigurationRegistry.resolve(appWindow)?.onArgumentsChanged?.call(
      appWindow,
    );
    if (mounted && widget.rebuildOnArgumentsChanged) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
