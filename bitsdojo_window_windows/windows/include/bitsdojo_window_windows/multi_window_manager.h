#ifndef MULTI_WINDOW_MANAGER_H_
#define MULTI_WINDOW_MANAGER_H_

#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <windows.h>

// Forward declarations
namespace flutter {
class FlutterEngine;
}

/// Manages multiple windows in a Flutter Windows application.
/// This class handles window creation, tracking, and lifecycle management.
class MultiWindowManager {
public:
  /// Window factory callback type
  /// Parameters: title, x, y, width, height
  /// Returns: HWND of created window, or nullptr on failure
  using WindowFactory =
      std::function<HWND(const wchar_t *title, int x, int y, int width,
                         int height, const char *name, const char *arguments)>;

  /// Modality of a new window relative to its opener. Mirrors the wire
  /// format of the 'openNewWindow' channel call, where the 'modality' key is
  /// absent for kNone — absent/unknown strings must decode to kNone.
  enum class WindowModality { kNone = 0, kModeless = 1, kModal = 2 };

  /// Get singleton instance
  static MultiWindowManager &GetInstance();

  /// Set the window factory callback
  /// This must be called before opening any secondary windows
  void SetWindowFactory(WindowFactory factory);

  /// Open a new window with the specified parameters
  /// Called by the plugin when Dart requests a new window.
  ///
  /// Creation is DEFERRED to the next message-loop turn. This method is
  /// invoked from a MethodChannel handler — i.e. from inside the calling
  /// engine's platform-message dispatch — and the factory builds a whole
  /// FlutterViewController for the new engine. Constructing engine #2
  /// re-entrantly inside engine #1's dispatch is exactly what the macOS
  /// plugin defers to the next main-queue turn, and doing it inline on
  /// Windows produced secondary windows whose view never presented a frame.
  ///
  /// [parent] is the OPENER's own top-level window; for kModeless/kModal the
  /// new window becomes owned by it (and for kModal the parent is disabled
  /// until the dialog closes). The WindowFactory ABI cannot carry a parent —
  /// runner apps implement it — so ownership is assigned post-creation.
  void OpenNewWindow(const char *name, const char *arguments, double width,
                     double height, double x, double y, HWND parent = nullptr,
                     WindowModality modality = WindowModality::kNone);

  /// The actual creation, run from the dispatch window's WndProc on a clean
  /// stack. Public only for that WndProc; not part of the API.
  void DoOpenNewWindow(const std::string &name, const std::string &arguments,
                       int width, int height, int x, int y, HWND parent,
                       WindowModality modality);

  /// Close a window by name
  void CloseWindow(const std::string &name);

  /// Close all tracked secondary windows before shutting down the app
  void CloseAllWindows(HWND except_window = nullptr);

  /// Get a window handle by name
  HWND GetWindow(const std::string &name);

  /// Called when a window is destroyed to clean up tracking
  void OnWindowDestroyed(HWND window);

  /// Invokes every OTHER window's closed notifier for [name], carrying the
  /// closed window's pending result (claimed — and erased — here, so a window
  /// reopened under the same name can never inherit it).
  void NotifyWindowClosed(const std::string &name, HWND closed_window);

  /// Store [result] (a JSON string from the dialog's `setWindowResult` call)
  /// to be delivered with the windowClosed broadcast when [window] actually
  /// closes. Last write wins: a Dart onClose veto can cancel a close after
  /// the result was set, and a later closeWithResult must replace it.
  void SetWindowResult(HWND window, const char *result);

  /// Register a window with its name for tracking
  void RegisterWindow(HWND window, const std::string &name);

  struct PendingWindowInfo {
    std::string name;
    std::string arguments;
  };

  /// Consume pending metadata for the next window being registered
  PendingWindowInfo ConsumePendingWindowInfo();

  /// Register a callback to send messages to a window
  using MessageSender = std::function<void(const char *arguments)>;
  void RegisterMessageSender(HWND window, MessageSender sender);

  /// Called in a window's engine when a DIFFERENT named window closes.
  /// [result] is the JSON string that window stored via SetWindowResult, or
  /// nullptr when it closed without ever setting one.
  using ClosedNotifier =
      std::function<void(const char *name, const char *result)>;
  void RegisterClosedNotifier(HWND window, ClosedNotifier notifier);

  /// Erases [dialog] from modal_parents_ and, if no OTHER modal dialog still
  /// holds the same parent, re-enables and refocuses it. Idempotent — the
  /// second call for the same dialog finds no entry and does nothing — so
  /// every close path can call it for one close. Public because the WM_CLOSE
  /// subclass hook calls it BEFORE destruction begins: re-enabling the owner
  /// only at WM_NCDESTROY (inside DestroyWindow) lets Win32 flash activation
  /// to an unrelated window while the owner is still disabled.
  void RestoreModalParent(HWND dialog);

private:
  MultiWindowManager() = default;
  ~MultiWindowManager() = default;

  // Prevent copying
  MultiWindowManager(const MultiWindowManager &) = delete;
  MultiWindowManager &operator=(const MultiWindowManager &) = delete;

  /// Send updateArguments message to a window
  void SendArgumentsUpdate(HWND window, const char *arguments);

  /// Lazily create the hidden message-only window that deferred opens are
  /// posted to. Returns nullptr on failure (caller falls back to inline
  /// creation).
  HWND EnsureDispatchWindow();

  /// Remove and return [window]'s pending result, or nullopt if none was set.
  /// Callers that destroy a window must claim the result BEFORE DestroyWindow:
  /// destruction re-enters OnWindowDestroyed, whose cleanup erases the entry.
  std::optional<std::string> TakePendingResult(HWND window);

  /// The fan-out half of NotifyWindowClosed, for callers that already claimed
  /// the pending result. [result] may be nullptr.
  void BroadcastWindowClosed(const std::string &name, HWND closed_window,
                             const char *result);

  /// Window tracking: name -> HWND
  std::map<std::string, HWND> windows_;

  /// Reverse mapping: HWND -> name (for cleanup)
  std::map<HWND, std::string> window_names_;

  /// Message senders: HWND -> callback
  std::map<HWND, MessageSender> message_senders_;

  /// Closed-window notifiers: HWND -> callback
  std::map<HWND, ClosedNotifier> closed_notifiers_;

  /// Pending info for windows under construction, consumed by registrar order
  std::deque<PendingWindowInfo> pending_windows_;

  /// Modal dialog -> the parent it disabled. Several dialogs can map to one
  /// parent; the parent is re-enabled only when its LAST dialog is erased.
  std::map<HWND, HWND> modal_parents_;

  /// Dialog window -> the result JSON it stored for its eventual close.
  /// Entries are claimed (erased) when the close is broadcast, and swept in
  /// OnWindowDestroyed regardless — the OS recycles HWND values, so a leaked
  /// entry could otherwise surface on an unrelated future window.
  std::map<HWND, std::string> pending_results_;

  /// Window factory callback
  WindowFactory window_factory_;

  /// Hidden message-only window that deferred opens are posted to
  HWND dispatch_window_ = nullptr;

  /// Mutex for thread safety
  std::recursive_mutex mutex_;
};

#endif // MULTI_WINDOW_MANAGER_H_
