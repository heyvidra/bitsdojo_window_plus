#include "include/bitsdojo_window_windows/bitsdojo_window_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <string>

#include "./bitsdojo_window_api.h"
#include "./bitsdojo_window.h"
#include "./native_ui.h"
#include "include/bitsdojo_window_windows/multi_window_manager.h"

// Helper function to get MultiWindowManager instance
MultiWindowManager &GetMultiWindowManagerInstance() {
  return MultiWindowManager::GetInstance();
}

const char kChannelName[] = "bitsdojo/window";
const auto bdwAPI = bitsdojo_window_api();

namespace {

class BitsdojoWindowPlugin : public flutter::Plugin {
public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  BitsdojoWindowPlugin(
      flutter::PluginRegistrarWindows *registrar,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);

  virtual ~BitsdojoWindowPlugin();

private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  static void OnCloseRequested(HWND window);

  // The registrar for this plugin.
  flutter::PluginRegistrarWindows *registrar_;

  // The channel to send menu item activations on.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // This engine's window identity, captured at registration and served to
  // Dart on request via `getWindowInfo`. The eager `windowReady` push fires
  // during plugin registration — before Dart main has installed its channel
  // handler — so it can be lost; a pull can't be.
  bool is_primary_ = false;
  std::string window_name_;
  std::string window_arguments_;

  static std::map<HWND, BitsdojoWindowPlugin *> instances_;
};

// static
std::map<HWND, BitsdojoWindowPlugin *> BitsdojoWindowPlugin::instances_;

// static
void BitsdojoWindowPlugin::OnCloseRequested(HWND window) {
  auto it = instances_.find(window);
  if (it != instances_.end()) {
    it->second->channel_->InvokeMethod(
        "closeRequested",
        std::make_unique<flutter::EncodableValue>((int64_t)window));
  }
}

// static
void BitsdojoWindowPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin =
      std::make_unique<BitsdojoWindowPlugin>(registrar, std::move(channel));

  HWND child_window = registrar->GetView()->GetNativeWindow();
  HWND window = GetParent(child_window);

  if (window) {
    bool isPrimary = instances_.empty();
    bitsdojo_window::attachMainWindow(window);
    bitsdojo_window::attachFlutterChildWindow(window, child_window);
    instances_[window] = plugin.get();
    bdwAPI->publicAPI->setCloseRequestedCallback(window, OnCloseRequested);

    // Sending a platform message for the primary window during native plugin
    // registration is racy on Windows: registration happens before Dart main
    // installs its MethodChannel handler, and some environments end up exiting
    // before a debug connection is established. The primary window can recover
    // its handle via getAppWindow() on the Dart side, so only secondary
    // windows need the eager windowReady notification here.
    flutter::EncodableMap args;
    args[flutter::EncodableValue("handle")] =
        flutter::EncodableValue((int64_t)window);
    args[flutter::EncodableValue("isPrimary")] =
        flutter::EncodableValue(isPrimary);

    // Consume pending name/arguments from MultiWindowManager
    auto pendingInfo =
        MultiWindowManager::GetInstance().ConsumePendingWindowInfo();
    std::string name = pendingInfo.name;
    if (!name.empty()) {
      args[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
    }
    std::string arguments = pendingInfo.arguments;
    if (!arguments.empty()) {
      args[flutter::EncodableValue("arguments")] =
          flutter::EncodableValue(arguments);
    }

    // Keep a copy on the instance for the Dart-initiated `getWindowInfo`
    // handshake — the push below races Dart main and can be lost.
    plugin->is_primary_ = isPrimary;
    plugin->window_name_ = name;
    plugin->window_arguments_ = arguments;

    if (!isPrimary) {
      plugin->channel_->InvokeMethod(
          "windowReady", std::make_unique<flutter::EncodableValue>(args));
    }

    // Register message sender for updateArguments
    MultiWindowManager::GetInstance().RegisterMessageSender(
        window, [plugin_pointer = plugin.get()](const char *args) {
          plugin_pointer->channel_->InvokeMethod(
              "updateArguments",
              std::make_unique<flutter::EncodableValue>(args ? args : ""));
        });

    // Register the closed-window notifier: this engine hears about every
    // OTHER named window that closes.
    MultiWindowManager::GetInstance().RegisterClosedNotifier(
        window, [plugin_pointer = plugin.get()](const char *name) {
          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("name")] =
              flutter::EncodableValue(name ? name : "");
          plugin_pointer->channel_->InvokeMethod(
              "windowClosed",
              std::make_unique<flutter::EncodableValue>(payload));
        });
  }

  plugin->channel_->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

BitsdojoWindowPlugin::BitsdojoWindowPlugin(
    flutter::PluginRegistrarWindows *registrar,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel)
    : registrar_(registrar), channel_(std::move(channel)) {}

BitsdojoWindowPlugin::~BitsdojoWindowPlugin() {
  // Find and remove this instance from the map
  for (auto it = instances_.begin(); it != instances_.end(); ++it) {
    if (it->second == this) {
      instances_.erase(it);
      break;
    }
  }
}

void BitsdojoWindowPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND child_window = registrar_->GetView()->GetNativeWindow();
  HWND window = GetParent(child_window);

  if (method_call.method_name().compare("getWindowInfo") == 0) {
    // THIS engine's window, derived from the registrar rather than from the
    // process-global `flutter_window` — that global is overwritten by every
    // attachMainWindow call, so with two engines it names whichever window
    // attached LAST. The Dart side of a secondary engine that trusted it via
    // getAppWindow() unlocked the wrong HWND's can-be-shown gate, and the
    // player window stayed hidden forever.
    flutter::EncodableMap info;
    info[flutter::EncodableValue("handle")] =
        flutter::EncodableValue((int64_t)window);
    info[flutter::EncodableValue("isPrimary")] =
        flutter::EncodableValue(is_primary_);
    if (!window_name_.empty()) {
      info[flutter::EncodableValue("name")] =
          flutter::EncodableValue(window_name_);
    }
    if (!window_arguments_.empty()) {
      info[flutter::EncodableValue("arguments")] =
          flutter::EncodableValue(window_arguments_);
    }
    result->Success(flutter::EncodableValue(info));
  } else if (method_call.method_name().compare("dragAppWindow") == 0) {
    bool callResult = bdwAPI->privateAPI->dragAppWindow(window);
    if (callResult) {
      result->Success();
    } else {
      result->Error("ERROR_DRAG_APP_WINDOW_FAILED",
                    "Could not drag app window");
    }
  } else if (method_call.method_name().compare("openNewWindow") == 0) {
    auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      auto name_it = args->find(flutter::EncodableValue("name"));
      const char *name = nullptr;
      std::string name_str;
      if (name_it != args->end() &&
          std::holds_alternative<std::string>(name_it->second)) {
        name_str = std::get<std::string>(name_it->second);
        name = name_str.c_str();
      }

      auto arguments_it = args->find(flutter::EncodableValue("arguments"));
      const char *arguments = nullptr;
      std::string arguments_str;
      if (arguments_it != args->end() &&
          std::holds_alternative<std::string>(arguments_it->second)) {
        arguments_str = std::get<std::string>(arguments_it->second);
        arguments = arguments_str.c_str();
      }

      auto width_it = args->find(flutter::EncodableValue("width"));
      double width = (width_it != args->end() &&
                      std::holds_alternative<double>(width_it->second))
                         ? std::get<double>(width_it->second)
                         : 0;

      auto height_it = args->find(flutter::EncodableValue("height"));
      double height = (height_it != args->end() &&
                       std::holds_alternative<double>(height_it->second))
                          ? std::get<double>(height_it->second)
                          : 0;

      auto x_it = args->find(flutter::EncodableValue("x"));
      double x =
          (x_it != args->end() && std::holds_alternative<double>(x_it->second))
              ? std::get<double>(x_it->second)
              : 0;

      auto y_it = args->find(flutter::EncodableValue("y"));
      double y =
          (y_it != args->end() && std::holds_alternative<double>(y_it->second))
              ? std::get<double>(y_it->second)
              : 0;

      // Use MultiWindowManager to create the window. The block-scope `extern`
      // redeclaration this used to carry landed inside the anonymous namespace,
      // so it named a NEW internal-linkage symbol that nothing defines — GCC
      // rejects it as "declared static but never defined". The file-scope
      // declaration at the top is the one that resolves.
      GetMultiWindowManagerInstance().OpenNewWindow(name, arguments, width,
                                                    height, x, y);

      result->Success();
    } else {
      result->Error("INVALID_ARGUMENTS", "Expected EncodableMap");
    }
  } else if (method_call.method_name().compare("hasWindow") == 0) {
    auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    std::string name_str;
    if (args) {
      auto name_it = args->find(flutter::EncodableValue("name"));
      if (name_it != args->end() &&
          std::holds_alternative<std::string>(name_it->second)) {
        name_str = std::get<std::string>(name_it->second);
      }
    }
    HWND named = name_str.empty()
                     ? nullptr
                     : MultiWindowManager::GetInstance().GetWindow(name_str);
    result->Success(
        flutter::EncodableValue(named != nullptr && IsWindow(named)));
  } else if (method_call.method_name().compare("closeWindow") == 0) {
    auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    std::string name_str;
    if (args) {
      auto name_it = args->find(flutter::EncodableValue("name"));
      if (name_it != args->end() &&
          std::holds_alternative<std::string>(name_it->second)) {
        name_str = std::get<std::string>(name_it->second);
      }
    }
    if (!name_str.empty()) {
      MultiWindowManager::GetInstance().CloseWindow(name_str);
    }
    result->Success();
  } else if (method_call.method_name().compare("showNativeAlert") == 0) {
    auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    int index = args ? bitsdojo_native_ui::ShowAlert(window, *args) : -1;
    result->Success(flutter::EncodableValue(index));
  } else if (method_call.method_name().compare("showNativeMenu") == 0) {
    auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    std::string picked =
        args ? bitsdojo_native_ui::ShowMenu(window, child_window, *args)
             : std::string();
    if (picked.empty()) {
      result->Success();  // Dismissed: null, not an empty id.
    } else {
      result->Success(flutter::EncodableValue(picked));
    }
  } else if (method_call.method_name().compare("terminateApp") == 0) {
    // Terminate the app by destroying the window.
    // This allows OnDestroy to run (cleaning up Flutter controller) while
    // message loop is still active.
    if (window) {
      MultiWindowManager::GetInstance().CloseAllWindows(window);
      DestroyWindow(window);
    } else {
      PostQuitMessage(0);
    }
    result->Success();
  } else {
    result->NotImplemented();
  }
}

} // namespace

void BitsdojoWindowPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  BitsdojoWindowPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
