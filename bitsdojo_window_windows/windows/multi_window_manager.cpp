#include "include/bitsdojo_window_windows/multi_window_manager.h"
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/standard_method_codec.h>
#include <vector>

namespace {

/// Parameters for a deferred window open, heap-allocated and carried through
/// a posted message. Ownership passes to the WndProc.
struct DeferredOpenParams {
  std::string name;
  std::string arguments;
  int width;
  int height;
  int x;
  int y;
};

constexpr UINT kDeferredOpenMessage = WM_APP + 0x77;

LRESULT CALLBACK DispatchWndProc(HWND hwnd, UINT message, WPARAM wparam,
                                 LPARAM lparam) {
  if (message == kDeferredOpenMessage) {
    std::unique_ptr<DeferredOpenParams> params(
        reinterpret_cast<DeferredOpenParams *>(lparam));
    if (params) {
      MultiWindowManager::GetInstance().DoOpenNewWindow(
          params->name, params->arguments, params->width, params->height,
          params->x, params->y);
    }
    return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

} // namespace

MultiWindowManager &MultiWindowManager::GetInstance() {
  static MultiWindowManager instance;
  return instance;
}

void MultiWindowManager::SetWindowFactory(WindowFactory factory) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  window_factory_ = factory;
}

HWND MultiWindowManager::EnsureDispatchWindow() {
  if (dispatch_window_ && IsWindow(dispatch_window_)) {
    return dispatch_window_;
  }
  static const wchar_t kClassName[] = L"BitsdojoWindowDispatch";
  WNDCLASS wc = {};
  wc.lpfnWndProc = DispatchWndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kClassName;
  // Fails with ERROR_CLASS_ALREADY_EXISTS on the second call; that is fine.
  RegisterClass(&wc);
  dispatch_window_ =
      CreateWindowEx(0, kClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                     wc.hInstance, nullptr);
  return dispatch_window_;
}

void MultiWindowManager::OpenNewWindow(const char *name, const char *arguments,
                                       double width, double height, double x,
                                       double y) {
  // Default size if not specified
  int w = (width == 0) ? 1280 : static_cast<int>(width);
  int h = (height == 0) ? 720 : static_cast<int>(height);

  // DEFER to the next message-loop turn. This method runs inside a
  // MethodChannel handler — the calling engine's platform-message dispatch —
  // and the factory constructs a complete FlutterViewController for the new
  // engine. Built re-entrantly on that stack, the second engine's view could
  // come up without ever presenting a frame; the macOS plugin defers the same
  // work to the next main-queue turn for the same reason. The message-only
  // dispatch window runs our WndProc from the main message loop, on a clean
  // stack.
  if (HWND dispatcher = EnsureDispatchWindow()) {
    auto params = std::make_unique<DeferredOpenParams>();
    params->name = name ? name : "";
    params->arguments = arguments ? arguments : "";
    params->width = w;
    params->height = h;
    params->x = static_cast<int>(x);
    params->y = static_cast<int>(y);
    if (PostMessage(dispatcher, kDeferredOpenMessage, 0,
                    reinterpret_cast<LPARAM>(params.get()))) {
      params.release(); // WndProc owns it now
      return;
    }
  }

  // Dispatch window or post failed: fall back to inline creation — the
  // pre-deferral behaviour, no worse than before.
  DoOpenNewWindow(name ? name : "", arguments ? arguments : "", w, h,
                  static_cast<int>(x), static_cast<int>(y));
}

void MultiWindowManager::DoOpenNewWindow(const std::string &name_str,
                                         const std::string &arguments,
                                         int w, int h, int x, int y) {
  {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    // Check if named window already exists
    if (!name_str.empty()) {
      auto it = windows_.find(name_str);
      if (it != windows_.end()) {
        HWND hwnd = it->second;
        if (IsWindow(hwnd)) {
          // Restore and activate existing window
          if (IsIconic(hwnd)) {
            ShowWindow(hwnd, SW_RESTORE);
          }
          SetForegroundWindow(hwnd);

          // Send updated arguments to existing window
          SendArgumentsUpdate(hwnd, arguments.c_str());
          return;
        } else {
          // Window was destroyed, clean up mapping
          windows_.erase(it);
          window_names_.erase(hwnd);
        }
      }
    }

    // Create new window
    if (!window_factory_) {
      return;
    }

    PendingWindowInfo pending_entry{name_str, arguments};
    pending_windows_.push_back(pending_entry);
  } // Lock released here to avoid deadlock during factory call

  // Create window via factory (RegisterWithRegistrar will be called inside here)
  HWND hwnd = window_factory_(L"Flutter", x, y, w, h,
                              name_str.empty() ? nullptr : name_str.c_str(),
                              arguments.empty() ? nullptr : arguments.c_str());

  {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    if (!hwnd) {
      // Factory failed: remove the specific entry we pushed (not blindly
      // pop_back, as another thread may have pushed since we released the lock)
      for (auto it = pending_windows_.rbegin(); it != pending_windows_.rend(); ++it) {
        if (it->name == name_str) {
          pending_windows_.erase(std::next(it).base());
          break;
        }
      }
    }

    if (hwnd && !name_str.empty()) {
      windows_[name_str] = hwnd;
      window_names_[hwnd] = name_str;
    }
  }
}

MultiWindowManager::PendingWindowInfo
MultiWindowManager::ConsumePendingWindowInfo() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  if (pending_windows_.empty()) {
    return {};
  }
  auto info = pending_windows_.front();
  pending_windows_.pop_front();
  return info;
}

void MultiWindowManager::SendArgumentsUpdate(HWND window,
                                             const char *arguments) {
  if (!window || !arguments)
    return;

  std::lock_guard<std::recursive_mutex> lock(mutex_);
  auto it = message_senders_.find(window);
  if (it != message_senders_.end()) {
    it->second(arguments);
  }
}

void MultiWindowManager::RegisterMessageSender(HWND window,
                                               MessageSender sender) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  message_senders_[window] = sender;
}

void MultiWindowManager::RegisterClosedNotifier(HWND window,
                                                ClosedNotifier notifier) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  closed_notifiers_[window] = notifier;
}

void MultiWindowManager::NotifyWindowClosed(const std::string &name,
                                            HWND closed_window) {
  // Copy under the lock, invoke outside it: a notifier runs Dart code that
  // can call straight back into this manager.
  std::vector<ClosedNotifier> to_notify;
  {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    for (const auto &[window, notifier] : closed_notifiers_) {
      if (window != closed_window && IsWindow(window)) {
        to_notify.push_back(notifier);
      }
    }
  }
  for (const auto &notifier : to_notify) {
    notifier(name.c_str());
  }
}

void MultiWindowManager::CloseWindow(const std::string &name) {
  HWND hwnd = nullptr;
  {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    auto it = windows_.find(name);
    if (it == windows_.end()) {
      return;
    }
    hwnd = it->second;
    // Erase by key BEFORE DestroyWindow: destruction re-enters
    // OnWindowDestroyed (WM_NCDESTROY subclass hook), which would otherwise
    // erase the element this iterator points to, invalidating it.
    windows_.erase(it);
    window_names_.erase(hwnd);
  }

  if (IsWindow(hwnd)) {
    DestroyWindow(hwnd);
  }

  // The mapping was erased above, so OnWindowDestroyed cannot broadcast
  // this close — do it here. Never double-fired for the same close.
  NotifyWindowClosed(name, hwnd);
}

void MultiWindowManager::CloseAllWindows(HWND except_window) {
  std::vector<HWND> windows_to_close;
  {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    windows_to_close.reserve(message_senders_.size());
    for (const auto &[window, _] : message_senders_) {
      if (window != nullptr && window != except_window && IsWindow(window)) {
        windows_to_close.push_back(window);
      }
    }
  }

  for (HWND window : windows_to_close) {
    DestroyWindow(window);
  }
}

HWND MultiWindowManager::GetWindow(const std::string &name) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);

  auto it = windows_.find(name);
  return (it != windows_.end()) ? it->second : nullptr;
}

void MultiWindowManager::OnWindowDestroyed(HWND window) {
  std::string closed_name;
  {
    std::lock_guard<std::recursive_mutex> lock(mutex_);

    message_senders_.erase(window);
    closed_notifiers_.erase(window);

    // Find and remove from mappings
    auto name_it = window_names_.find(window);
    if (name_it != window_names_.end()) {
      closed_name = name_it->second;
      windows_.erase(closed_name);
      window_names_.erase(name_it);
    }
  }

  // A name still mapped here means the close was NOT initiated through
  // CloseWindow (which erases the mapping and broadcasts itself) — the user
  // closed it, or its own Dart did. Broadcast outside the lock.
  if (!closed_name.empty()) {
    NotifyWindowClosed(closed_name, window);
  }
}

void MultiWindowManager::RegisterWindow(HWND window, const std::string &name) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);

  if (!name.empty() && window) {
    windows_[name] = window;
    window_names_[window] = name;
  }
}
