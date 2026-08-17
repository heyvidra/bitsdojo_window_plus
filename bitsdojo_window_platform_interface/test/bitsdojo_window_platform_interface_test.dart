import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:bitsdojo_window_platform_interface/method_channel_bitsdojo_window.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDesktopWindow extends DesktopWindow {
  Rect _rect = const Rect.fromLTWH(100, 100, 800, 600);
  Alignment? _alignment;
  bool _visible = true;
  bool _alwaysOnTop = false;
  bool _isMaximized = false;
  double _titleBarHeight = 32;
  bool _hasShadow = true;

  @override
  bool get hasShadow => _hasShadow;
  @override
  set hasShadow(bool v) => _hasShadow = v;

  @override
  int? get handle => 1;
  @override
  double get scaleFactor => 1.0;
  @override
  Rect get rect => _rect;
  @override
  set rect(Rect r) => _rect = r;
  @override
  Offset get position => _rect.topLeft;
  @override
  set position(Offset p) =>
      _rect = Rect.fromLTWH(p.dx, p.dy, _rect.width, _rect.height);
  @override
  Size get size => _rect.size;
  @override
  set size(Size s) =>
      _rect = Rect.fromLTWH(_rect.left, _rect.top, s.width, s.height);
  @override
  set minSize(Size? s) {}
  @override
  set maxSize(Size? s) {}
  @override
  Size get screenSize => const Size(1920, 1080);
  @override
  Size get workingScreenSize => const Size(1920, 1040);
  @override
  Rect get workingScreenRect => const Rect.fromLTWH(0, 0, 1920, 1040);
  @override
  Alignment? get alignment => _alignment;
  @override
  set alignment(Alignment? a) => _alignment = a;
  @override
  set title(String t) {}
  @override
  bool get visible => _visible;
  @override
  bool get isVisible => _visible;
  @override
  set visible(bool v) => _visible = v;
  @override
  void show() => _visible = true;
  @override
  void hide() => _visible = false;
  @override
  void close() {}
  @override
  void minimize() {}
  @override
  void maximize() => _isMaximized = true;
  @override
  void maximizeOrRestore() => _isMaximized = !_isMaximized;
  @override
  void toggleFullScreen() {}
  @override
  void restore() => _isMaximized = false;
  @override
  void startDragging() {}
  @override
  bool get alwaysOnTop => _alwaysOnTop;
  @override
  set alwaysOnTop(bool v) => _alwaysOnTop = v;
  @override
  Size get titleBarButtonSize => const Size(46, 32);
  @override
  double get titleBarHeight => _titleBarHeight;
  @override
  set titleBarHeight(double h) => _titleBarHeight = h;
  @override
  double get borderSize => 1.0;
  @override
  bool get isMaximized => _isMaximized;
  @override
  VoidCallback? get onClose => null;
  @override
  set onClose(VoidCallback? cb) {}
  @override
  VoidCallback? get onArgumentsChanged => null;
  @override
  set onArgumentsChanged(VoidCallback? cb) {}
  @override
  set backgroundEffect(WindowEffect e) {}
  @override
  bool get isMainWindow => true;
  @override
  int get depth => 0;
  @override
  String? get name => null;
  @override
  Map<String, dynamic>? get arguments => null;
  @override
  Future<void> openNewWindow({
    String? name,
    Size? size,
    Offset? position,
    Map<String, dynamic>? arguments,
  }) async {}
}

class FakePlatform extends BitsdojoWindowPlatform with MockPlatformInterfaceMixin {
  final DesktopWindow _window = MockDesktopWindow();

  @override
  void doWhenWindowReady(VoidCallback cb) => cb();

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
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('native UI', () {
    const channel = MethodChannel('bitsdojo/window');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('menu items serialize with nested submenus and null-id separators', () {
      const items = [
        NativeMenuItem('copy', 'Copy'),
        NativeMenuItem.separator(),
        NativeMenuItem('view', 'View', enabled: false, submenu: [
          NativeMenuItem('wrap', 'Wrap', checked: true),
        ]),
      ];

      final maps = [for (final item in items) item.toMap()];
      expect(maps[0], {
        'id': 'copy',
        'label': 'Copy',
        'enabled': true,
        'checked': false,
      });
      expect(maps[1]['id'], isNull);
      expect(maps[2]['enabled'], isFalse);
      expect((maps[2]['submenu'] as List).single, {
        'id': 'wrap',
        'label': 'Wrap',
        'enabled': true,
        'checked': true,
      });
    });

    test('showNativeAlert passes the request through and returns the index',
        () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return 1;
      });

      final index = await MethodChannelBitsdojoWindow().showNativeAlert(
        title: 'Delete?',
        message: 'This cannot be undone.',
        buttons: ['Delete', 'Cancel'],
        style: NativeAlertStyle.critical,
      );

      expect(index, 1);
      expect(seen?.method, 'showNativeAlert');
      expect(seen?.arguments['buttons'], ['Delete', 'Cancel']);
      expect(seen?.arguments['style'], NativeAlertStyle.critical.index);
    });

    test('a missing plugin reads as a dismissal, not an exception', () async {
      // No mock handler installed: the same shape a platform without native UI
      // gives, so callers only ever branch on the value.
      final platform = MethodChannelBitsdojoWindow();
      expect(await platform.showNativeAlert(title: 'Hi'), -1);
      expect(
        await platform.showNativeMenu(const [NativeMenuItem('copy', 'Copy')]),
        isNull,
      );
    });
  });

  group('BitsdojoWindowPlatform', () {
    test('instance defaults to MethodChannelBitsdojoWindow', () {
      expect(BitsdojoWindowPlatform.instance, isNotNull);
    });

    test('instance can be replaced with a mock', () {
      final fake = FakePlatform();
      BitsdojoWindowPlatform.instance = fake;
      expect(BitsdojoWindowPlatform.instance, same(fake));
    });

    test('hasWindow defaults to false — absence, not an error', () async {
      expect(await FakePlatform().hasWindow('pet'), isFalse);
    });

    test('closeWindow defaults to a completed no-op', () async {
      await FakePlatform().closeWindow('pet');
    });

    test('onWindowClosed is settable and clearable', () {
      final platform = FakePlatform();
      String? seen;
      platform.onWindowClosed = (name) => seen = name;
      platform.onWindowClosed?.call('pet');
      expect(seen, 'pet');
      platform.onWindowClosed = null;
      expect(platform.onWindowClosed, isNull);
    });

    test('doWhenWindowReady calls callback synchronously in fake', () {
      final fake = FakePlatform();
      bool called = false;
      fake.doWhenWindowReady(() => called = true);
      expect(called, isTrue);
    });
  });

  group('DesktopWindow', () {
    late MockDesktopWindow window;

    setUp(() => window = MockDesktopWindow());

    test('initial rect is set correctly', () {
      expect(window.rect, const Rect.fromLTWH(100, 100, 800, 600));
    });

    test('notifyWindowChanged fires changes listeners until removed', () {
      var notified = 0;
      void listener() => notified++;

      window.changes.addListener(listener);
      window.notifyWindowChanged();
      window.notifyWindowChanged();
      expect(notified, 2);

      window.changes.removeListener(listener);
      window.notifyWindowChanged();
      expect(notified, 2);
    });

    test('show/hide toggles isVisible', () {
      window.hide();
      expect(window.isVisible, isFalse);
      window.show();
      expect(window.isVisible, isTrue);
    });

    test('maximize/restore toggles isMaximized', () {
      window.maximize();
      expect(window.isMaximized, isTrue);
      window.restore();
      expect(window.isMaximized, isFalse);
    });

    test('maximizeOrRestore toggles state', () {
      expect(window.isMaximized, isFalse);
      window.maximizeOrRestore();
      expect(window.isMaximized, isTrue);
      window.maximizeOrRestore();
      expect(window.isMaximized, isFalse);
    });

    test('alwaysOnTop setter works', () {
      window.alwaysOnTop = true;
      expect(window.alwaysOnTop, isTrue);
      window.alwaysOnTop = false;
      expect(window.alwaysOnTop, isFalse);
    });

    test('hasShadow setter works', () {
      window.hasShadow = true;
      expect(window.hasShadow, isTrue);
      window.hasShadow = false;
      expect(window.hasShadow, isFalse);
    });

    test('position setter updates rect', () {
      window.position = const Offset(200, 300);
      expect(window.position.dx, 200);
      expect(window.position.dy, 300);
      expect(window.size.width, 800);
      expect(window.size.height, 600);
    });

    test('size setter preserves position', () {
      window.size = const Size(1024, 768);
      expect(window.size.width, 1024);
      expect(window.size.height, 768);
      expect(window.position.dx, 100);
      expect(window.position.dy, 100);
    });

    test('capabilities defaults to no extra features', () {
      expect(window.capabilities.supportsBackgroundEffects, isFalse);
      expect(window.capabilities.supportsTitleBarButtonVisibility, isFalse);
    });

    test('depth is 0 for main window', () {
      expect(window.depth, 0);
      expect(window.isMainWindow, isTrue);
    });
  });

  group('WindowEffect enum', () {
    test('has 5 values', () {
      expect(WindowEffect.values.length, 5);
    });

    test('values are in expected order', () {
      expect(WindowEffect.values[0], WindowEffect.disabled);
      expect(WindowEffect.values[1], WindowEffect.transparent);
      expect(WindowEffect.values[2], WindowEffect.acrylic);
      expect(WindowEffect.values[3], WindowEffect.mica);
      expect(WindowEffect.values[4], WindowEffect.tabbed);
    });
  });

  group('DesktopWindowCapabilities', () {
    test('defaults all to false', () {
      const caps = DesktopWindowCapabilities();
      expect(caps.supportsBackgroundEffects, isFalse);
      expect(caps.supportsTitleBarButtonVisibility, isFalse);
      expect(caps.supportsTitleBarButtonOffset, isFalse);
    });

    test('can enable individual capabilities', () {
      const caps = DesktopWindowCapabilities(supportsBackgroundEffects: true);
      expect(caps.supportsBackgroundEffects, isTrue);
      expect(caps.supportsTitleBarButtonVisibility, isFalse);
    });
  });
}
