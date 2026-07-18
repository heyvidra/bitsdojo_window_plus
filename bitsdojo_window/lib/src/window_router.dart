import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:flutter/widgets.dart';

typedef WindowBuilder = Widget Function(
    BuildContext context, Map<String, dynamic>? arguments);

class WindowRouter {
  static final Map<String, WindowBuilder> _builders = {};

  static void register({required String name, required WindowBuilder builder}) {
    _builders[name] = builder;
  }

  static void registerAll(Map<String, WindowBuilder> builders) {
    _builders.addAll(builders);
  }

  static Widget build(BuildContext context, DesktopWindow window,
      {required Widget defaultWidget}) {
    final name = window.name;
    if (name != null && _builders.containsKey(name)) {
      return _builders[name]!(context, window.arguments);
    }
    return defaultWidget;
  }
}
