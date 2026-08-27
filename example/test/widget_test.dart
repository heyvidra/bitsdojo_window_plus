import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDesktopWindow extends DesktopWindow {
  Rect _rect = const Rect.fromLTWH(0, 0, 900, 700);
  Alignment? _alignment = Alignment.center;
  bool _isVisible = true;
  bool _alwaysOnTop = false;
  double _titleBarHeight = 50;
  Map<String, dynamic>? _arguments;
  VoidCallback? _onClose;
  VoidCallback? _onArgumentsChanged;
  bool _hasShadow = true;

  @override
  bool get hasShadow => _hasShadow;

  @override
  set hasShadow(bool v) => _hasShadow = v;

  @override
  int? get handle => 42;

  @override
  double get scaleFactor => 1;

  @override
  Rect get rect => _rect;

  @override
  set rect(Rect newRect) => _rect = newRect;

  @override
  Offset get position => _rect.topLeft;

  @override
  set position(Offset newPosition) {
    _rect = Rect.fromLTWH(
      newPosition.dx,
      newPosition.dy,
      _rect.width,
      _rect.height,
    );
  }

  @override
  Size get size => _rect.size;

  @override
  set size(Size newSize) {
    _rect = Rect.fromLTWH(_rect.left, _rect.top, newSize.width, newSize.height);
  }

  @override
  set minSize(Size? newSize) {}

  @override
  set maxSize(Size? newSize) {}

  @override
  Size get screenSize => const Size(1440, 900);

  @override
  Size get workingScreenSize => const Size(1440, 860);

  @override
  Rect get workingScreenRect => const Rect.fromLTWH(0, 0, 1440, 860);

  @override
  Alignment? get alignment => _alignment;

  @override
  set alignment(Alignment? newAlignment) => _alignment = newAlignment;

  @override
  set title(String newTitle) {}

  @override
  bool get isVisible => _isVisible;

  @override
  void show() => _isVisible = true;

  @override
  void hide() => _isVisible = false;

  @override
  void close() {}

  @override
  void minimize() {}

  @override
  void maximize() {}

  @override
  void maximizeOrRestore() {}

  @override
  void toggleFullScreen() {}

  @override
  void restore() {}

  @override
  void startDragging() {}

  @override
  bool get alwaysOnTop => _alwaysOnTop;

  @override
  set alwaysOnTop(bool onTop) => _alwaysOnTop = onTop;

  @override
  Size get titleBarButtonSize => const Size(46, 32);

  @override
  double get titleBarHeight => _titleBarHeight;

  @override
  set titleBarHeight(double height) => _titleBarHeight = height;

  @override
  double get borderSize => 1;

  @override
  bool get isMaximized => false;

  @override
  VoidCallback? get onClose => _onClose;

  @override
  set onClose(VoidCallback? callback) => _onClose = callback;

  @override
  VoidCallback? get onArgumentsChanged => _onArgumentsChanged;

  @override
  set onArgumentsChanged(VoidCallback? callback) =>
      _onArgumentsChanged = callback;

  @override
  set backgroundEffect(WindowEffect effect) {}

  @override
  bool get isMainWindow => true;

  @override
  int get depth => 0;

  @override
  String? get name => null;

  @override
  Map<String, dynamic>? get arguments => _arguments;

  // openNewWindow/openDialog inherited from the concrete base, which
  // delegates to BitsdojoWindowPlatform.instance (the fake platform below).

  @override
  void setWindowTitleBarButtonVisibility(
    DesktopWindowButton button,
    bool visible,
  ) {}

  @override
  void setWindowTitleBarButtonOffset(
    DesktopWindowButton button,
    Offset offset,
  ) {}

  // Linux-only API accessed via `as dynamic` in main.dart's WindowButtons.
  bool isButtonVisible(DesktopWindowButton button) => true;
}

class _FakeBitsdojoWindowPlatform extends BitsdojoWindowPlatform {
  final DesktopWindow _window = _FakeDesktopWindow();

  @override
  void doWhenWindowReady(VoidCallback callback) => callback();

  @override
  DesktopWindow get appWindow => _window;

  @override
  DesktopWindow getWindowForHandle(int handle) => _window;

  @override
  Future<void> openNewWindow({
    String? name,
    Size? size,
    Offset? position,
    Map<String, dynamic>? arguments,
    WindowModality modality = WindowModality.none,
  }) async {}
}

void main() {
  testWidgets('renders multi-window example shell', (
    WidgetTester tester,
  ) async {
    BitsdojoWindowPlatform.instance = _FakeBitsdojoWindowPlatform();

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Multi-Window Dashboard'), findsOneWidget);
    expect(find.text('PRIMARY'), findsOneWidget);
    expect(find.textContaining('HANDLE 42'), findsOneWidget);
    expect(find.text('Open Regular Window'), findsOneWidget);
    expect(find.text('Toggle Fullscreen'), findsOneWidget);
  });
}
