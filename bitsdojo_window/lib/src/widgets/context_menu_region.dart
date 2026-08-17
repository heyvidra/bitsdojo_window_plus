import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:flutter/widgets.dart';

import '../app_window.dart';

/// Pops an OS-native menu when [child] is right-clicked.
///
/// Sugar over `showNativeMenu` — it forwards the click's `globalPosition`, which
/// is what puts the menu under the pointer.
///
/// ```dart
/// ContextMenuRegion(
///   items: const [
///     NativeMenuItem('copy', 'Copy'),
///     NativeMenuItem.separator(),
///     NativeMenuItem('paste', 'Paste', enabled: false),
///   ],
///   onSelected: (id) => print(id),
///   child: const Text('right-click me'),
/// )
/// ```
///
/// For a menu whose contents depend on what was clicked, pass [itemsBuilder]
/// instead of [items] — it runs at click time.
class ContextMenuRegion extends StatelessWidget {
  const ContextMenuRegion({
    super.key,
    this.items,
    this.itemsBuilder,
    this.onSelected,
    this.onDismissed,
    required this.child,
  }) : assert(
          (items == null) != (itemsBuilder == null),
          'Give ContextMenuRegion either items or itemsBuilder, not both',
        );

  final List<NativeMenuItem>? items;

  /// Builds the menu at click time, receiving the click position in logical
  /// pixels from the window's top-left.
  final List<NativeMenuItem> Function(Offset position)? itemsBuilder;

  /// Called with the [NativeMenuItem.id] of the picked entry.
  final ValueChanged<String>? onSelected;

  /// Called instead of [onSelected] when the menu closed without a pick.
  final VoidCallback? onDismissed;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Deferring to the child keeps this wrapper from swallowing hits on
      // transparent areas the child doesn't paint.
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapDown: (details) async {
        final position = details.globalPosition;
        final menu = items ?? itemsBuilder!(position);
        if (menu.isEmpty) return;
        final picked = await showNativeMenu(menu, position: position);
        if (picked == null) {
          onDismissed?.call();
        } else {
          onSelected?.call(picked);
        }
      },
      child: child,
    );
  }
}
