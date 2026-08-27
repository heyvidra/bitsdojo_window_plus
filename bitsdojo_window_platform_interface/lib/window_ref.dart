import 'bitsdojo_window_platform_interface.dart';

/// A handle to a window opened by `openNewWindow`.
///
/// Windows are addressed by name across every platform (it is the only
/// identifier that survives the Linux one-process-per-window model), so this
/// is a thin wrapper over that name — worth having because before it existed,
/// an unnamed window was unreachable the moment `openNewWindow` returned.
/// Unnamed windows now get an auto-generated name precisely so a ref can
/// always be handed back.
class WindowRef {
  const WindowRef(this.name);

  /// The name the window was opened under — the caller's, or auto-generated.
  final String name;

  /// Whether the window currently exists.
  Future<bool> exists() => BitsdojoWindowPlatform.instance.hasWindow(name);

  /// Closes the window. A no-op when it is already gone.
  Future<void> close() => BitsdojoWindowPlatform.instance.closeWindow(name);

  /// Delivers new [arguments] to the window and focuses it — the named-reuse
  /// semantics of `openNewWindow`, addressed through the ref.
  Future<void> update(Map<String, dynamic> arguments) =>
      BitsdojoWindowPlatform.instance
          .openNewWindow(name: name, arguments: arguments);

  @override
  String toString() => 'WindowRef($name)';
}
