import 'package:bitsdojo_window_windows/bitsdojo_window_windows.dart'
    show WinDesktopWindow;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../app_window.dart';

class WindowBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double? width;

  WindowBorder({Key? key, required this.child, required this.color, this.width})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool isWindowsApp =
        (!kIsWeb) && (defaultTargetPlatform == TargetPlatform.windows);
    bool isLinuxApp =
        (!kIsWeb) && (defaultTargetPlatform == TargetPlatform.linux);

    // Only show border on Windows and Linux
    if (!(isWindowsApp || isLinuxApp)) {
      return child;
    }

    var borderWidth = width ?? 1;
    var leftBorderWidth = width ?? 1;
    var rightBorderWidth = width ?? 1;
    var bottomBorderWidth = width ?? 1;
    var topBorderWidth = width ?? 1;

    if (appWindow is WinDesktopWindow) {
      appWindow as WinDesktopWindow..setWindowCutOnMaximize(borderWidth.ceil());
    }

    if (isWindowsApp) {
      leftBorderWidth += 1 / appWindow.scaleFactor;
      rightBorderWidth += 1 / appWindow.scaleFactor;
      bottomBorderWidth += 1 / appWindow.scaleFactor;
      topBorderWidth += 1 / appWindow.scaleFactor;
    }
    final topBorderSide = BorderSide(color: this.color, width: topBorderWidth);
    final leftBorderSide =
        BorderSide(color: this.color, width: leftBorderWidth);
    final rightBorderSide =
        BorderSide(color: this.color, width: rightBorderWidth);
    final bottomBorderSide =
        BorderSide(color: this.color, width: bottomBorderWidth);

    return Container(
        child: child,
        decoration: BoxDecoration(
            border: Border(
                top: topBorderSide,
                left: leftBorderSide,
                right: rightBorderSide,
                bottom: bottomBorderSide)));
  }
}
