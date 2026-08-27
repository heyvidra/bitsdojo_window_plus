#include "include/bitsdojo_window_windows/multi_window_manager.h"
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/standard_method_codec.h>
#include <utility>
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
  HWND parent;
  MultiWindowManager::WindowModality modality;
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
          params->x, params->y, params->parent, params->modality);
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
                                       double y, HWND parent,
                                       WindowModality modality) {
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
    params->parent = parent;
    params->modality = modality;
    if (PostMessage(dispatcher, kDeferredOpenMessage, 0,
                    reinterpret_cast<LPARAM>(params.get()))) {
      params.release(); // WndProc owns it now
      return;
    }
  }

  // Dispatch window or post failed: fall back to inline creation — the
  // pre-deferral behaviour, no worse than before.
  DoOpenNewWindow(name ? name : "", arguments ? arguments : "", w, h,
                  static_cast<int>(x), static_cast<int>(y), parent, modality);
}

void MultiWindowManager::DoOpenNewWindow(const std::string &name_str,
                                         const std::string &arguments,
                                         int w, int h, int x, int y,
                                         HWND parent,
                                         WindowModality modality) {
  {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    // Check if named window already exists
    if (!name_str.empty()) {
      auto it = windows_.find(name_str);
      if (it != windows_.end()) {
        HWND hwnd = it->second;
        if (IsWindow(hwnd)) {
          // Reuse path: modality is deliberately IGNORED here — the existing
          // window keeps the ownership it was created with; only focus and
          // arguments are refreshed.
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

  // The open was deferred through PostMessage, so the opener can be gone by
  // the time we run — a dead parent gets neither ownership nor modality.
  if (parent && !IsWindow(parent)) {
    parent = nullptr;
  }
  if (!parent) {
    modality = WindowModality::kNone;
  }

  // Classic Win32 modal order: the owner is disabled BEFORE the dialog
  // exists, so no input can slip into the parent during construction.
  if (modality == WindowModality::kModal) {
    EnableWindow(parent, FALSE);
  }

  // Create window via factory (RegisterWithRegistrar will be called inside here)
  HWND hwnd = window_factory_(L"Flutter", x, y, w, h,
                              name_str.empty() ? nullptr : name_str.c_str(),
                              arguments.empty() ? nullptr : arguments.c_str());

  if (hwnd && modality != WindowModality::kNone) {
    // The WindowFactory ABI cannot carry a parent (runner apps in the wild
    // implement it), so ownership is assigned post-creation. On a top-level
    // window GWLP_HWNDPARENT sets the OWNER, not a WS_CHILD parent: the new
    // window stays above the parent and minimizes with it.
    SetWindowLongPtr(hwnd, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(parent));
  }

  bool reenable_parent = false;
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
      if (modality == WindowModality::kModal) {
        // Undo the pre-factory disable — unless a modal dialog from an
        // earlier open still holds this parent.
        reenable_parent = true;
        for (const auto &[dialog, dialog_parent] : modal_parents_) {
          if (dialog_parent == parent) {
            reenable_parent = false;
            break;
          }
        }
      }
    }

    if (hwnd && !name_str.empty()) {
      windows_[name_str] = hwnd;
      window_names_[hwnd] = name_str;
    }

    if (hwnd && modality == WindowModality::kModal) {
      modal_parents_[hwnd] = parent;
    }
  }

  if (reenable_parent) {
    EnableWindow(parent, TRUE);
  }

  if (hwnd && modality == WindowModality::kModal) {
    // Re-assert the disable. The factory ran outside the lock and pumps
    // messages while constructing the view; a sibling modal dialog destroyed
    // during that window found no modal_parents_ entry for this in-flight
    // dialog and re-enabled the shared parent. Idempotent when nothing
    // intervened.
    EnableWindow(parent, FALSE);
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

void MultiWindowManager::SetWindowResult(HWND window, const char *result) {
  if (!window || !result) {
    return;
  }
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  // Overwrite, don't insert-once: a Dart onClose veto can cancel the close
  // that followed a setWindowResult, and the NEXT closeWithResult must win.
  pending_results_[window] = result;
}

std::optional<std::string> MultiWindowManager::TakePendingResult(HWND window) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  auto it = pending_results_.find(window);
  if (it == pending_results_.end()) {
    return std::nullopt;
  }
  std::string result = std::move(it->second);
  pending_results_.erase(it);
  return result;
}

void MultiWindowManager::NotifyWindowClosed(const std::string &name,
                                            HWND closed_window) {
  std::optional<std::string> result = TakePendingResult(closed_window);
  BroadcastWindowClosed(name, closed_window,
                        result ? result->c_str() : nullptr);
}

void MultiWindowManager::BroadcastWindowClosed(const std::string &name,
                                               HWND closed_window,
                                               const char *result) {
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
    notifier(name.c_str(), result);
  }
}

void MultiWindowManager::RestoreModalParent(HWND dialog) {
  HWND parent = nullptr;
  {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    auto it = modal_parents_.find(dialog);
    if (it == modal_parents_.end()) {
      return;
    }
    parent = it->second;
    modal_parents_.erase(it);
    for (const auto &[other_dialog, other_parent] : modal_parents_) {
      if (other_parent == parent) {
        // A sibling modal dialog still holds this parent disabled.
        return;
      }
    }
  }
  // All three calls fail harmlessly on an already-destroyed parent, which
  // covers owner destruction tearing down its owned dialogs.
  EnableWindow(parent, TRUE);
  SetForegroundWindow(parent);
  SetActiveWindow(parent);
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

  // Claim the pending result BEFORE DestroyWindow: destruction synchronously
  // re-enters OnWindowDestroyed (WM_NCDESTROY), whose cleanup sweeps
  // pending_results_ — claiming afterwards would broadcast a null result for
  // a dialog that set one.
  std::optional<std::string> pending_result = TakePendingResult(hwnd);

  // Re-enable the owner BEFORE destroying a modal dialog: if the owner is
  // still disabled when its modal window is destroyed, Win32 activates a
  // random other application's window instead of the owner.
  RestoreModalParent(hwnd);

  if (IsWindow(hwnd)) {
    DestroyWindow(hwnd);
  }

  // The mapping was erased above, so OnWindowDestroyed cannot broadcast
  // this close — do it here. Never double-fired for the same close.
  BroadcastWindowClosed(name, hwnd,
                        pending_result ? pending_result->c_str() : nullptr);
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
  // Only reached on ACTUAL destruction (WM_NCDESTROY) — a WM_CLOSE the Dart
  // side vetoes never gets here, so a vetoed modal keeps its parent disabled.
  RestoreModalParent(window);

  std::string closed_name;
  std::optional<std::string> pending_result;
  {
    std::lock_guard<std::recursive_mutex> lock(mutex_);

    message_senders_.erase(window);
    closed_notifiers_.erase(window);

    // Claim any stored result unconditionally — even when the broadcast
    // happened elsewhere (CloseWindow claims first) or won't happen at all
    // (unnamed window). The OS recycles HWND values, so a leaked entry could
    // be delivered for an unrelated future window on the same handle.
    auto result_it = pending_results_.find(window);
    if (result_it != pending_results_.end()) {
      pending_result = std::move(result_it->second);
      pending_results_.erase(result_it);
    }

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
    BroadcastWindowClosed(closed_name, window,
                          pending_result ? pending_result->c_str() : nullptr);
  }
}

void MultiWindowManager::RegisterWindow(HWND window, const std::string &name) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);

  if (!name.empty() && window) {
    windows_[name] = window;
    window_names_[window] = name;
  }
}
