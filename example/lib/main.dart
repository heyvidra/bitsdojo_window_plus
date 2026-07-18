import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';

void main() {
  runBitsdojoWindowApp(
    app: const MyApp(),
    routes: {
      'inspector_window': (context, arguments) => const MyHomePage(),
      'singleton_window': (context, arguments) => const SingletonDemoWindow(),
    },
    windowConfigurations: _buildWindowConfigurations(),
  );
}

List<WindowConfiguration> _buildWindowConfigurations() {
  final isLinux = Platform.isLinux;
  return [
    WindowConfiguration(
      mainWindow: true,
      size: const Size(1100, 820),
      alignment: Alignment.center,
      title: 'Bitsdojo Multi-Window Dashboard',
      backgroundEffect: platformWindowCapabilities.supportsBackgroundEffects
          ? WindowEffect.acrylic
          : WindowEffect.disabled,
      alwaysOnTop: false,
      readyAnimation: isLinux
          ? const WindowReadyAnimation.none()
          : const WindowReadyAnimation.popIn(),
    ),
    WindowConfiguration(
      buttonVisibilityBuilder: (window) {
        final args = window.arguments;
        if (args != null && args['onlyClose'] == true) {
          return const {
            DesktopWindowButton.close: true,
            DesktopWindowButton.minimize: false,
            DesktopWindowButton.zoom: false,
          };
        }
        return null;
      },
      titleBuilder: (window) => 'Child Window - ${window.name ?? 'Untitled'}',
      backgroundEffect: platformWindowCapabilities.supportsBackgroundEffects
          ? WindowEffect.acrylic
          : WindowEffect.disabled,
      alwaysOnTop: false,
      readyAnimation: isLinux
          ? const WindowReadyAnimation.none()
          : const WindowReadyAnimation.popIn(),
    ),
  ];
}

bool get _supportsBackgroundEffects =>
    appWindow.capabilities.supportsBackgroundEffects;
bool get _supportsTitleBarButtonVisibility =>
    appWindow.capabilities.supportsTitleBarButtonVisibility;
bool get _supportsTitleBarButtonOffset =>
    appWindow.capabilities.supportsTitleBarButtonOffset;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bitsdojo Window Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6FBFA),
      ),
      home: RoutedWindowHost(
        onCloseRequested: _handleWindowCloseRequest,
        defaultChild: const MyHomePage(),
      ),
    );
  }
}

Future<bool> _handleWindowCloseRequest(
  BuildContext context,
  DesktopWindow window,
) async {
  if (!window.isMainWindow) {
    return true;
  }

  final shouldClose = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Exit Confirmation'),
        content: const Text(
          'Closing the MAIN window will terminate the entire application.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit App', style: TextStyle(color: Colors.red)),
          ),
        ],
      );
    },
  );

  return shouldClose ?? false;
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _titleController = TextEditingController();
  WindowEffect _currentEffect = WindowEffect.disabled;
  double _closeOffsetX = 0;
  double _closeOffsetY = 0;
  double _titleBarHeight = 50;
  bool _alwaysOnTop = false;
  Size? _minConstraint;
  Size? _maxConstraint;
  int _singletonCounter = 0;
  int _inspectorCounter = 0;
  final Map<DesktopWindowButton, bool> _buttonVisibility = {
    DesktopWindowButton.close: true,
    DesktopWindowButton.minimize: true,
    DesktopWindowButton.zoom: true,
  };

  @override
  void initState() {
    super.initState();
    _titleController.text = appWindow.isMainWindow
        ? 'Bitsdojo Multi-Window Dashboard'
        : 'Child Window - ${appWindow.name ?? 'Untitled'}';
    _titleBarHeight = _clampSliderValue(appWindow.titleBarHeight, 24, 90);
    _alwaysOnTop = appWindow.alwaysOnTop;
    _currentEffect = _supportsBackgroundEffects
        ? WindowEffect.acrylic
        : WindowEffect.disabled;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.teal.withValues(alpha: 0.18),
              Colors.white,
              Colors.blueGrey.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: WindowBorder(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
          width: 1,
          child: ClipRect(
            child: Column(
              children: [
                WindowTitleBarBox(child: _buildWindowChrome(context)),
                Expanded(
                  child: ClipRect(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                      child: Column(
                        children: [
                          _buildHeader(context),
                          const SizedBox(height: 24),
                          _buildFeatureGrid(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWindowChrome(BuildContext context) {
    final label = appWindow.isMainWindow
        ? 'Bitsdojo Multi-Window Dashboard'
        : 'Child Window - ${appWindow.name ?? 'Untitled'}';
    final chromeHeight = _titleBarHeight;

    return Container(
      height: chromeHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: MoveWindow(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const WindowButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final argsJson = _formatArguments(appWindow.arguments);
    final workingSize = appWindow.workingScreenSize;
    final fullSize = appWindow.screenSize;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildBadge(
                appWindow.isMainWindow ? 'PRIMARY' : 'SECONDARY',
                appWindow.isMainWindow ? Colors.orange : Colors.teal,
              ),
              _buildBadge('DEPTH ${appWindow.depth}', Colors.blueGrey),
              _buildBadge('HANDLE ${appWindow.handle}', Colors.indigo),
              _buildBadge(
                appWindow.isMaximized ? 'MAXIMIZED' : 'NORMAL',
                appWindow.isMaximized ? Colors.pink : Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Multi-Window Dashboard',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            appWindow.isMainWindow
                ? 'A control surface that exercises the full desktop window API.'
                : 'This child window rebuilds from live window arguments and shares the same control surface.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.black87),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildInfoTile('Scale', appWindow.scaleFactor.toStringAsFixed(2)),
              _buildInfoTile(
                'Frame',
                '${appWindow.size.width.toInt()} x ${appWindow.size.height.toInt()}',
              ),
              _buildInfoTile(
                'Position',
                '${appWindow.position.dx.toInt()}, ${appWindow.position.dy.toInt()}',
              ),
              _buildInfoTile(
                'Screen',
                '${fullSize.width.toInt()} x ${fullSize.height.toInt()}',
              ),
              _buildInfoTile(
                'Work Area',
                '${workingSize.width.toInt()} x ${workingSize.height.toInt()}',
              ),
              _buildInfoTile(
                'Title Buttons',
                '${appWindow.titleBarButtonSize.width.toStringAsFixed(0)} x '
                    '${appWindow.titleBarButtonSize.height.toStringAsFixed(0)}',
              ),
            ],
          ),
          if (argsJson != null) ...[
            const SizedBox(height: 20),
            _buildDataCard('Window Arguments', argsJson, Colors.deepOrange),
          ],
        ],
      ),
    );
  }

  Widget _buildFeatureGrid() {
    return Wrap(
      spacing: 24,
      runSpacing: 24,
      alignment: WrapAlignment.center,
      children: [
        _buildSection('Window Management', [
          _buildButton(
            icon: Icons.add_to_photos,
            label: 'Open Regular Window',
            onPressed: () => appWindow.openNewWindow(
              arguments: {'onlyClose': false, 'source': 'regular'},
            ),
          ),
          _buildButton(
            icon: Icons.pin_invoke,
            label: 'Open Named Inspector',
            color: Colors.teal,
            onPressed: _openInspectorWindow,
          ),
          _buildButton(
            icon: Icons.play_circle_fill,
            label: 'Update Singleton Video Window',
            color: Colors.deepPurple,
            onPressed: _openSingletonWindow,
          ),
          _buildButton(
            icon: Icons.crop_free,
            label: 'Spawn Custom 800 x 320',
            onPressed: () => appWindow.openNewWindow(
              size: const Size(800, 320),
              position: const Offset(150, 150),
              arguments: {'onlyClose': true, 'kind': 'custom'},
            ),
          ),
          _buildButton(
            icon: Icons.visibility_off,
            label: 'Hide for 1.2s Then Show',
            onPressed: _hideAndRestoreWindow,
          ),
          _buildButton(
            icon: Icons.close,
            label: appWindow.isMainWindow
                ? 'Close Main Window (Intercepted)'
                : 'Close This Window',
            color: Colors.redAccent,
            onPressed: () => appWindow.close(),
          ),
        ]),
        _buildSection('Window State', [
          _buildButton(
            icon: Icons.minimize,
            label: 'Minimize',
            onPressed: () => appWindow.minimize(),
          ),
          _buildButton(
            icon: Icons.copy_all,
            label: 'Maximize or Restore',
            onPressed: () => setState(() => appWindow.maximizeOrRestore()),
          ),
          _buildButton(
            icon: Icons.crop_square,
            label: 'Maximize',
            onPressed: () => setState(() => appWindow.maximize()),
          ),
          _buildButton(
            icon: Icons.filter_none,
            label: 'Restore',
            onPressed: () => setState(() => appWindow.restore()),
          ),
          _buildButton(
            icon: Icons.fullscreen,
            label: 'Toggle Fullscreen',
            onPressed: () => appWindow.toggleFullScreen(),
          ),
          _buildToggle('Always on Top', _alwaysOnTop, (value) {
            setState(() => _alwaysOnTop = value);
            appWindow.alwaysOnTop = value;
          }),
        ]),
        _buildSection('Geometry & Constraints', [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSmallAction(
                'Center',
                () => appWindow.alignment = Alignment.center,
              ),
              _buildSmallAction(
                'Top Left',
                () => appWindow.alignment = Alignment.topLeft,
              ),
              _buildSmallAction(
                'Bottom Right',
                () => appWindow.alignment = Alignment.bottomRight,
              ),
              _buildSmallAction(
                'Move +40/+40',
                () => appWindow.position =
                    appWindow.position + const Offset(40, 40),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSmallAction(
                '640 x 420',
                () => appWindow.size = const Size(640, 420),
              ),
              _buildSmallAction(
                '900 x 700',
                () => appWindow.size = const Size(900, 700),
              ),
              _buildSmallAction(
                '1100 x 820',
                () => appWindow.size = const Size(1100, 820),
              ),
              _buildSmallAction(
                'Rect 80,80',
                () => appWindow.rect = Rect.fromLTWH(
                  80,
                  80,
                  appWindow.size.width,
                  appWindow.size.height,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSmallAction(
                'Animate 640 x 420',
                () => appWindow.animateSize(const Size(640, 420)),
              ),
              _buildSmallAction(
                'Animate Center',
                () => appWindow.animateTo(
                  size: const Size(900, 700),
                  alignment: Alignment.center,
                  duration: const Duration(milliseconds: 280),
                ),
              ),
              _buildSmallAction(
                'Animate Bottom Right',
                () => appWindow.animateTo(
                  size: const Size(540, 360),
                  alignment: Alignment.bottomRight,
                  duration: const Duration(milliseconds: 280),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildButton(
            icon: Icons.lock_outline,
            label: 'Set Min Size 520 x 420',
            onPressed: () {
              const size = Size(520, 420);
              setState(() => _minConstraint = size);
              appWindow.minSize = size;
            },
          ),
          _buildButton(
            icon: Icons.lock_open,
            label: 'Clear Min Size',
            onPressed: () {
              setState(() => _minConstraint = null);
              appWindow.minSize = null;
            },
          ),
          _buildButton(
            icon: Icons.aspect_ratio,
            label: 'Set Max Size 1280 x 900',
            onPressed: () {
              const size = Size(1280, 900);
              setState(() => _maxConstraint = size);
              appWindow.maxSize = size;
            },
          ),
          _buildButton(
            icon: Icons.open_in_full,
            label: 'Clear Max Size',
            onPressed: () {
              setState(() => _maxConstraint = null);
              appWindow.maxSize = null;
            },
          ),
          const SizedBox(height: 8),
          _buildInlineStat('Min', _formatOptionalSize(_minConstraint)),
          _buildInlineStat('Max', _formatOptionalSize(_maxConstraint)),
          _buildInlineStat('Border', appWindow.borderSize.toStringAsFixed(1)),
        ]),
        _buildSection('Title Bar & Buttons', [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Window Title',
              border: OutlineInputBorder(),
            ),
            onSubmitted: _applyTitle,
          ),
          const SizedBox(height: 12),
          _buildButton(
            icon: Icons.title,
            label: 'Apply Title',
            onPressed: () => _applyTitle(_titleController.text),
          ),
          const SizedBox(height: 8),
          _buildValueSlider('Title Bar Height', _titleBarHeight, 24, 90, (
            value,
          ) {
            setState(() => _titleBarHeight = value);
            appWindow.titleBarHeight = value;
          }),
          const Divider(),
          _buildPlatformNote(
            _supportsTitleBarButtonVisibility
                ? 'Traffic-light/button visibility is supported on this platform.'
                : 'Button visibility control is currently only supported on macOS and Linux.',
          ),
          const SizedBox(height: 8),
          _buildVisibilityControls(),
          const Divider(),
          _buildPlatformNote(
            _supportsTitleBarButtonOffset
                ? 'Close button offset is supported on macOS.'
                : 'Close button offset is currently only supported on macOS.',
          ),
          _buildOffsetControls(),
        ]),
        _buildSection('Effects & Support Matrix', [
          _buildEffectSelector(),
          const SizedBox(height: 12),
          _buildInlineStat(
            'Background Effects',
            _supportsBackgroundEffects ? 'Supported' : 'Not supported',
          ),
          _buildInlineStat(
            'Button Visibility',
            _supportsTitleBarButtonVisibility ? 'Supported' : 'Not supported',
          ),
          _buildInlineStat(
            'Button Offset',
            _supportsTitleBarButtonOffset ? 'Supported' : 'Not supported',
          ),
          const SizedBox(height: 16),
          _buildDataCard('Current Effect', _currentEffect.name, Colors.teal),
        ]),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: color != null ? Colors.white : null,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallAction(String label, VoidCallback onPressed) {
    return ActionChip(label: Text(label), onPressed: onPressed);
  }

  Widget _buildVisibilityControls() {
    return Opacity(
      opacity: _supportsTitleBarButtonVisibility ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !_supportsTitleBarButtonVisibility,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildMiniToggle('Close', DesktopWindowButton.close),
              const SizedBox(width: 8),
              _buildMiniToggle('Min', DesktopWindowButton.minimize),
              const SizedBox(width: 8),
              _buildMiniToggle('Zoom', DesktopWindowButton.zoom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniToggle(String label, DesktopWindowButton button) {
    final isVisible = _buttonVisibility[button] ?? true;
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        IconButton(
          onPressed: () {
            final nextValue = !isVisible;
            setState(() => _buttonVisibility[button] = nextValue);
            appWindow.setWindowTitleBarButtonVisibility(button, nextValue);
          },
          icon: Icon(
            isVisible ? Icons.visibility : Icons.visibility_off,
            size: 18,
          ),
        ),
      ],
    );
  }

  Widget _buildOffsetControls() {
    return Opacity(
      opacity: _supportsTitleBarButtonOffset ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !_supportsTitleBarButtonOffset,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _buildValueSlider('X', _closeOffsetX, -50, 50, (value) {
                  setState(() => _closeOffsetX = value);
                  _applyCloseButtonOffset();
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildValueSlider('Y', _closeOffsetY, -50, 50, (value) {
                  setState(() => _closeOffsetY = value);
                  _applyCloseButtonOffset();
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildValueSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    final clampedValue = _clampSliderValue(value, min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${clampedValue.toStringAsFixed(0)}',
          style: const TextStyle(fontSize: 11),
        ),
        Slider(value: clampedValue, min: min, max: max, onChanged: onChanged),
      ],
    );
  }

  Widget _buildEffectSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Background Effect',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _supportsBackgroundEffects ? null : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        Opacity(
          opacity: _supportsBackgroundEffects ? 1 : 0.45,
          child: IgnorePointer(
            ignoring: !_supportsBackgroundEffects,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: WindowEffect.values.map((effect) {
                return ChoiceChip(
                  label: Text(
                    effect.name,
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: _currentEffect == effect,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() => _currentEffect = effect);
                    appWindow.backgroundEffect = effect;
                  },
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataCard(String title, String value, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformNote(String text) {
    return Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[700]));
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _openSingletonWindow() async {
    _singletonCounter++;
    await appWindow.openNewWindow(
      name: 'singleton_window',
      arguments: {'number': _singletonCounter, 'source': 'singleton'},
    );
  }

  Future<void> _openInspectorWindow() async {
    _inspectorCounter++;
    await appWindow.openNewWindow(
      name: 'inspector_window',
      size: const Size(920, 760),
      position: const Offset(120, 120),
      arguments: {
        'number': _inspectorCounter,
        'source': 'inspector',
        'onlyClose': false,
      },
    );
  }

  Future<void> _hideAndRestoreWindow() async {
    appWindow.hide();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    appWindow.show();
  }

  void _applyTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    appWindow.title = trimmed;
  }

  void _applyCloseButtonOffset() {
    appWindow.setWindowTitleBarButtonOffset(
      DesktopWindowButton.close,
      Offset(_closeOffsetX, _closeOffsetY),
    );
  }

  String _formatOptionalSize(Size? size) {
    if (size == null) return 'unbounded';
    return '${size.width.toInt()} x ${size.height.toInt()}';
  }

  double _clampSliderValue(double value, double min, double max) {
    if (value.isNaN) {
      return min;
    }
    return value.clamp(min, max).toDouble();
  }

  String? _formatArguments(Map<String, dynamic>? arguments) {
    if (arguments == null || arguments.isEmpty) {
      return null;
    }
    return const JsonEncoder.withIndent('  ').convert(arguments);
  }
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final buttonColors = WindowButtonColors(
      iconNormal: Theme.of(context).colorScheme.primary,
      mouseOver: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      mouseDown: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
      iconMouseOver: Theme.of(context).colorScheme.primary,
      iconMouseDown: Theme.of(context).colorScheme.primary,
    );

    final closeButtonColors = WindowButtonColors(
      mouseOver: const Color(0xFFD32F2F),
      mouseDown: const Color(0xFFB71C1C),
      iconNormal: Theme.of(context).colorScheme.primary,
      iconMouseOver: Colors.white,
    );

    bool isButtonVisible(DesktopWindowButton button) {
      if (Platform.isLinux) {
        return (appWindow as dynamic).isButtonVisible(button);
      }
      return true;
    }

    return Row(
      children: [
        if (isButtonVisible(DesktopWindowButton.minimize))
          MinimizeWindowButton(colors: buttonColors),
        if (isButtonVisible(DesktopWindowButton.zoom))
          MaximizeWindowButton(colors: buttonColors),
        if (isButtonVisible(DesktopWindowButton.close))
          CloseWindowButton(colors: closeButtonColors),
      ],
    );
  }
}

class SingletonDemoWindow extends StatelessWidget {
  const SingletonDemoWindow({super.key});

  @override
  Widget build(BuildContext context) {
    final arguments = appWindow.arguments ?? const <String, dynamic>{};
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.deepPurple.withValues(alpha: 0.10),
              const Color(0xFFF7FBFA),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: WindowBorder(
          color: Colors.deepPurple.withValues(alpha: 0.3),
          width: 1,
          child: Column(
            children: [
              WindowTitleBarBox(
                child: Container(
                  color: Colors.deepPurple.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Named Singleton Window',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      MoveWindow(
                        child: Container(
                          alignment: Alignment.centerLeft,
                          height: 50,
                        ),
                      ),
                      const WindowButtons(),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This window keeps the same native instance and only updates its arguments when reopened by name.',
                        style: TextStyle(fontSize: 15),
                      ),
                      const SizedBox(height: 16),
                      _SingletonStat(
                        label: 'Window Name',
                        value: appWindow.name ?? 'singleton_window',
                      ),
                      _SingletonStat(
                        label: 'Invocation Count',
                        value: '${arguments['number'] ?? 0}',
                      ),
                      _SingletonStat(
                        label: 'Arguments',
                        value: const JsonEncoder.withIndent(
                          '  ',
                        ).convert(arguments),
                      ),
                      const Spacer(),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => appWindow.alwaysOnTop = true,
                            icon: const Icon(Icons.vertical_align_top),
                            label: const Text('Pin On Top'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => appWindow.toggleFullScreen(),
                            icon: const Icon(Icons.fullscreen),
                            label: const Text('Toggle Fullscreen'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => appWindow.close(),
                            icon: const Icon(Icons.close),
                            label: const Text('Close'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SingletonStat extends StatelessWidget {
  const _SingletonStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(value),
        ],
      ),
    );
  }
}
