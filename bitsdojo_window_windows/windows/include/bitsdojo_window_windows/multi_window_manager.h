#ifndef MULTI_WINDOW_MANAGER_H_
#define MULTI_WINDOW_MANAGER_H_

#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
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
  void OpenNewWindow(const char *name, const char *arguments, double width,
                     double height, double x, double y);

  /// The actual creation, run from the dispatch window's WndProc on a clean
  /// stack. Public only for that WndProc; not part of the API.
  void DoOpenNewWindow(const std::string &name, const std::string &arguments,
                       int width, int height, int x, int y);

  /// Close a window by name
  void CloseWindow(const std::string &name);

  /// Close all tracked secondary windows before shutting down the app
  void CloseAllWindows(HWND except_window = nullptr);

  /// Get a window handle by name
  HWND GetWindow(const std::string &name);

  /// Called when a window is destroyed to clean up tracking
  void OnWindowDestroyed(HWND window);

  /// Invokes every OTHER window's closed notifier for [name].
  void NotifyWindowClosed(const std::string &name, HWND closed_window);

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
  using ClosedNotifier = std::function<void(const char *name)>;
  void RegisterClosedNotifier(HWND window, ClosedNotifier notifier);

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

  /// Window factory callback
  WindowFactory window_factory_;

  /// Hidden message-only window that deferred opens are posted to
  HWND dispatch_window_ = nullptr;

  /// Mutex for thread safety
  std::recursive_mutex mutex_;
};

#endif // MULTI_WINDOW_MANAGER_H_
