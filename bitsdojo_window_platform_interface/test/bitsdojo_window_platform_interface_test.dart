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
  bool get isVisible => _visible;
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
  // openNewWindow/openDialog inherited: the concrete base delegates to
  // BitsdojoWindowPlatform.instance (FakePlatform in these tests).
}

class FakePlatform extends BitsdojoWindowPlatform with MockPlatformInterfaceMixin {
  final DesktopWindow _window = MockDesktopWindow();

  @override
  void doWhenWindowReady(VoidCallback cb) => cb();

  @override
  DesktopWindow get appWindow => _window;

  @override
  DesktopWindow getWindowForHandle(int handle) => _window;

  /// (name, modality) of every open request, so tests can assert both the
  /// auto-generated name and the modality the public API resolved to.
  final List<(String?, WindowModality)> openCalls = [];

  @override
  Future<void> openNewWindow({
    String? name,
    Size? size,
    Offset? position,
    Map<String, dynamic>? arguments,
    WindowModality modality = WindowModality.none,
  }) async {
    openCalls.add((name, modality));
  }
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
      // The literal, not `.index` on both sides — that form compares the enum
      // to itself and would keep passing if the values were reordered, which is
      // exactly the break it looks like it is guarding against. 2 is what
      // `case 2:` matches in NativeUI.swift, windows/native_ui.cpp and
      // linux/native_ui.cpp.
      expect(seen?.arguments['style'], 2);
    });

    test('wire values the three native switches match are pinned', () {
      // Each of these ordinals is read by a bare `case N:` in native code that
      // Dart cannot see, so reordering an enum silently changes behaviour on
      // every platform. Appending stays safe; renumbering does not.
      expect(NativeAlertStyle.values.map((s) => s.index), [0, 1, 2]);
      expect(WindowEventCode.values.map((c) => c.index),
          [0, 1, 2, 3, 4, 5, 6]);
      expect(DesktopWindowButton.values.map((b) => b.index), [0, 1, 2]);
      // WindowModality crosses the channel by NAME, not index: the string
      // literals below are what native `openNewWindow` handlers compare
      // against, so a rename is a wire-format break even though a reorder
      // is not.
      expect(WindowModality.values.map((m) => m.name),
          ['none', 'modeless', 'modal']);
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

  group('getRectOnScreen', () {
    // A screen that is neither at the origin nor square, so an off-by-a-width
    // bug can't hide behind zeros or symmetry.
    const screen = Rect.fromLTWH(100, 50, 1000, 800);
    const size = Size(400, 300);

    test('anchors the window inside the screen for every named alignment', () {
      expect(getRectOnScreen(size, Alignment.topLeft, screen),
          const Rect.fromLTRB(100, 50, 500, 350));
      expect(getRectOnScreen(size, Alignment.topCenter, screen),
          const Rect.fromLTRB(400, 50, 800, 350));
      expect(getRectOnScreen(size, Alignment.topRight, screen),
          const Rect.fromLTRB(700, 50, 1100, 350));
      expect(getRectOnScreen(size, Alignment.centerLeft, screen),
          const Rect.fromLTRB(100, 300, 500, 600));
      expect(getRectOnScreen(size, Alignment.center, screen),
          const Rect.fromLTRB(400, 300, 800, 600));
      expect(getRectOnScreen(size, Alignment.centerRight, screen),
          const Rect.fromLTRB(700, 300, 1100, 600));
      expect(getRectOnScreen(size, Alignment.bottomCenter, screen),
          const Rect.fromLTRB(400, 550, 800, 850));
      expect(getRectOnScreen(size, Alignment.bottomRight, screen),
          const Rect.fromLTRB(700, 550, 1100, 850));
    });

    test('bottomLeft sits on the screen, not one width to the left of it', () {
      // Regression: this returned Rect.fromLTRB(-300, 550, 100, 850) — the
      // window placed entirely off the left edge — because the old code
      // subtracted the window width from the screen's LEFT edge.
      expect(getRectOnScreen(size, Alignment.bottomLeft, screen),
          const Rect.fromLTRB(100, 550, 500, 850));
    });

    test('an alignment that is not one of the nine named ones still places',
        () {
      // Regression: anything outside the named set fell through to Rect.zero,
      // collapsing the window instead of positioning it.
      expect(getRectOnScreen(size, const Alignment(0, 0.5), screen),
          const Rect.fromLTRB(400, 425, 800, 725));
    });

    test('every alignment keeps the requested size', () {
      for (final alignment in const [
        Alignment.topLeft,
        Alignment.bottomLeft,
        Alignment.bottomRight,
        Alignment(-0.3, 0.7),
      ]) {
        expect(getRectOnScreen(size, alignment, screen).size, size);
      }
    });
  });

  group('window events', () {
    test('decodes each code with its payload', () {
      expect(decodeWindowEvent({'type': 0}), isA<WindowFocused>());
      expect(decodeWindowEvent({'type': 1}), isA<WindowBlurred>());
      expect(decodeWindowEvent({'type': 4}), isA<WindowMinimized>());
      expect(decodeWindowEvent({'type': 5}), isA<WindowMaximized>());
      expect(decodeWindowEvent({'type': 6}), isA<WindowRestored>());

      final moved = decodeWindowEvent({'type': 2, 'x': 12.0, 'y': -34.0});
      expect((moved as WindowMoved).position, const Offset(12, -34));

      final resized =
          decodeWindowEvent({'type': 3, 'width': 800, 'height': 600.5});
      // Ints are accepted for geometry: the standard codec picks int over
      // double for whole numbers, so a whole-pixel size arrives as an int.
      expect((resized as WindowResized).size, const Size(800, 600.5));
    });

    test('an unknown or malformed event decodes to null, never throws', () {
      expect(decodeWindowEvent({'type': 99}), isNull);
      expect(decodeWindowEvent({'type': -1}), isNull);
      expect(decodeWindowEvent({'type': 'focused'}), isNull);
      expect(decodeWindowEvent(const {}), isNull);
      // Geometry codes without geometry: dropping beats a bogus Offset.zero.
      expect(decodeWindowEvent({'type': 2}), isNull);
      expect(decodeWindowEvent({'type': 3, 'width': 800}), isNull);
    });

    test('events reach listeners and stop after cancel', () async {
      final window = MockDesktopWindow();
      final seen = <WindowEvent>[];
      final subscription = window.events.listen(seen.add);
      addTearDown(subscription.cancel);

      window.emitWindowEvent(const WindowFocused());
      window.emitWindowEvent(const WindowMoved(Offset(5, 6)));
      await pumpEventQueue();
      expect(seen, hasLength(2));
      expect((seen[1] as WindowMoved).position, const Offset(5, 6));

      await subscription.cancel();
      window.emitWindowEvent(const WindowBlurred());
      await pumpEventQueue();
      expect(seen, hasLength(2));
    });

    test('emitting with nobody listening is harmless', () {
      // Broadcast streams drop events that arrive unheard; the point is that
      // native code can emit freely without checking for subscribers.
      MockDesktopWindow().emitWindowEvent(const WindowFocused());
    });
  });

  group('Display', () {
    test('parses a full payload', () {
      final display = Display.fromMap({
        'id': '4',
        'name': 'Dell S2716DG',
        'x': -832.0,
        'y': -1440.0,
        'width': 2560.0,
        'height': 1440.0,
        'workX': -832.0,
        'workY': -1409.0,
        'workWidth': 2560.0,
        'workHeight': 1409.0,
        'scaleFactor': 1.0,
        'isPrimary': false,
      })!;
      expect(display.id, '4');
      expect(display.bounds, const Rect.fromLTWH(-832, -1440, 2560, 1440));
      expect(display.workArea.top, -1409);
      expect(display.isPrimary, isFalse);
    });

    test('a missing work area falls back to the full bounds', () {
      final display = Display.fromMap({
        'x': 0,
        'y': 0,
        'width': 1280.0,
        'height': 900.0,
      })!;
      expect(display.workArea, display.bounds);
      expect(display.scaleFactor, 1.0);
    });

    test('without bounds there is no display at all', () {
      expect(Display.fromMap(const {'name': 'nowhere'}), isNull);
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

  group('close hub, dialogs and refs', () {
    late FakePlatform platform;

    setUp(() {
      platform = FakePlatform();
      BitsdojoWindowPlatform.instance = platform;
    });

    test('openNewWindow auto-names and returns a working ref', () async {
      final window = MockDesktopWindow();
      final a = await window.openNewWindow();
      final b = await window.openNewWindow();
      expect(a.name, startsWith('bdw#'));
      expect(a.name, isNot(b.name));
      expect(platform.openCalls.map((c) => c.$2),
          everyElement(WindowModality.none));
      // The ref's verbs address the platform by that name.
      expect(await a.exists(), isFalse); // default hasWindow answer
    });

    test('openDialog resolves with the result closeWithResult stored',
        () async {
      final window = MockDesktopWindow();
      final future = window.openDialog(name: 'confirm-a');
      expect(platform.openCalls.single, ('confirm-a', WindowModality.modal));

      WindowCloseHub.notifyClosed('confirm-a', '{"ok": true, "n": 1}');
      expect(await future, {'ok': true, 'n': 1});
    });

    test('modal: false opens a modeless dialog', () async {
      final window = MockDesktopWindow();
      final future = window.openDialog(name: 'confirm-b', modal: false);
      expect(platform.openCalls.single, ('confirm-b', WindowModality.modeless));
      WindowCloseHub.notifyClosed('confirm-b');
      expect(await future, isNull);
    });

    test('a plain close and a malformed result both read as null', () async {
      final window = MockDesktopWindow();
      final plain = window.openDialog(name: 'plain');
      WindowCloseHub.notifyClosed('plain');
      expect(await plain, isNull);

      final malformed = window.openDialog(name: 'malformed');
      WindowCloseHub.notifyClosed('malformed', 'not json {');
      expect(await malformed, isNull);
    });

    test('re-registering a pending name returns the SAME future', () async {
      // openDialog with an existing name focuses the existing dialog, so both
      // callers are waiting on the same window and must get the same answer.
      final first = WindowCloseHub.registerDialog('shared');
      final second = WindowCloseHub.registerDialog('shared');
      WindowCloseHub.notifyClosed('shared', '{"who": "both"}');
      expect(await first, {'who': 'both'});
      expect(await second, {'who': 'both'});
    });

    test('notifyClosed fans out to the stream and the legacy callback',
        () async {
      final fromStream = <String>[];
      final fromLegacy = <String>[];
      final sub = WindowCloseHub.closed.listen(fromStream.add);
      platform.onWindowClosed = fromLegacy.add;

      WindowCloseHub.notifyClosed('fan-out');
      await Future<void>.delayed(Duration.zero);

      expect(fromStream, ['fan-out']);
      expect(fromLegacy, ['fan-out']);
      await sub.cancel();
    });

    test('abortDialog fails the await instead of hanging it', () async {
      final future = WindowCloseHub.registerDialog('doomed');
      WindowCloseHub.abortDialog('doomed', StateError('spawn failed'),
          StackTrace.current);
      await expectLater(future, throwsStateError);
    });
  });
}
