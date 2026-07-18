#include "include/bitsdojo_window_windows/multi_window_manager.h"
#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/standard_method_codec.h>
#include <vector>

MultiWindowManager &MultiWindowManager::GetInstance() {
  static MultiWindowManager instance;
  return instance;
}

void MultiWindowManager::SetWindowFactory(WindowFactory factory) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  window_factory_ = factory;
}

void MultiWindowManager::OpenNewWindow(const char *name, const char *arguments,
                                       double width, double height, double x,
                                       double y) {
  std::string name_str = name ? name : "";

  // Default size if not specified
  int w = (width == 0) ? 1280 : static_cast<int>(width);
  int h = (height == 0) ? 720 : static_cast<int>(height);

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
          SendArgumentsUpdate(hwnd, arguments);
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

      PendingWindowInfo pending_entry{name_str, arguments ? arguments : ""};
    pending_windows_.push_back(pending_entry);
  } // Lock released here to avoid deadlock during factory call

  // Create window via factory (RegisterWithRegistrar will be called inside here)
  HWND hwnd = window_factory_(L"Flutter",
                              static_cast<int>(x), static_cast<int>(y),
                              static_cast<int>(w), static_cast<int>(h), name,
                              arguments);

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

void MultiWindowManager::CloseWindow(const std::string &name) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);

  auto it = windows_.find(name);
  if (it != windows_.end()) {
    HWND hwnd = it->second;
    if (IsWindow(hwnd)) {
      DestroyWindow(hwnd);
    }
    window_names_.erase(hwnd);
    windows_.erase(it);
  }
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
  std::lock_guard<std::recursive_mutex> lock(mutex_);

  message_senders_.erase(window);

  // Find and remove from mappings
  auto name_it = window_names_.find(window);
  if (name_it != window_names_.end()) {
    std::string name = name_it->second;
    windows_.erase(name);
    window_names_.erase(name_it);
  }
}

void MultiWindowManager::RegisterWindow(HWND window, const std::string &name) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);

  if (!name.empty() && window) {
    windows_[name] = window;
    window_names_[window] = name;
  }
}
