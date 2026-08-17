/// How prominent a native alert looks: maps to `NSAlert.Style` on macOS, the
/// `MB_ICON*` flags on Windows and `GtkMessageType` on Linux.
enum NativeAlertStyle { info, warning, critical }

/// One entry in a native popup menu.
///
/// [id] is what `showNativeMenu` returns when the entry is picked, so it only
/// has to be unique within the menu. A null [id] — see
/// [NativeMenuItem.separator] — draws a divider that can't be picked.
class NativeMenuItem {
  const NativeMenuItem(
    this.id,
    this.label, {
    this.enabled = true,
    this.checked = false,
    this.submenu,
  });

  const NativeMenuItem.separator()
      : id = null,
        label = '',
        enabled = false,
        checked = false,
        submenu = null;

  final String? id;
  final String label;
  final bool enabled;
  final bool checked;

  /// Nested entries. An entry that owns a submenu opens it instead of being
  /// picked, so its own [id] is never returned.
  final List<NativeMenuItem>? submenu;

  Map<String, Object?> toMap() => {
        'id': id,
        'label': label,
        'enabled': enabled,
        'checked': checked,
        if (submenu != null)
          'submenu': [for (final item in submenu!) item.toMap()],
      };
}
