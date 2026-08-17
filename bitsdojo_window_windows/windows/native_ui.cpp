#include "./native_ui.h"

// GetDpiForMonitor. Per-monitor DPI is the whole point of enumerating displays
// on a mixed-DPI desktop, so this is worth the Shcore link.
#include <shellscalingapi.h>

#include <optional>
#include <vector>

namespace bitsdojo_native_ui {

namespace {

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::string GetString(const flutter::EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  if (value == nullptr || !std::holds_alternative<std::string>(*value)) {
    return std::string();
  }
  return std::get<std::string>(*value);
}

bool GetBool(const flutter::EncodableMap& map, const char* key,
             bool fallback) {
  const auto* value = Find(map, key);
  if (value == nullptr || !std::holds_alternative<bool>(*value)) {
    return fallback;
  }
  return std::get<bool>(*value);
}

std::optional<double> GetDouble(const flutter::EncodableMap& map,
                                const char* key) {
  const auto* value = Find(map, key);
  if (value == nullptr) return std::nullopt;
  if (std::holds_alternative<double>(*value)) {
    return std::get<double>(*value);
  }
  // The standard codec picks int32 or int64 by magnitude, so an int-valued
  // coordinate can arrive as either. TryGetLongValue covers both.
  if (auto number = value->TryGetLongValue()) {
    return static_cast<double>(*number);
  }
  return std::nullopt;
}

int GetInt(const flutter::EncodableMap& map, const char* key, int fallback) {
  const auto* value = Find(map, key);
  if (value == nullptr) return fallback;
  if (auto number = value->TryGetLongValue()) {
    return static_cast<int>(*number);
  }
  return fallback;
}

std::string Utf8(const wchar_t* utf16) {
  if (utf16 == nullptr || utf16[0] == L'\0') return std::string();
  int size = WideCharToMultiByte(CP_UTF8, 0, utf16, -1, nullptr, 0, nullptr,
                                 nullptr);
  if (size <= 1) return std::string();
  // size counts the terminating NUL, which std::string carries implicitly.
  std::string result(static_cast<size_t>(size) - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, utf16, -1, result.data(), size, nullptr,
                      nullptr);
  return result;
}

std::wstring Utf16(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                 static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      result.data(), size);
  return result;
}

// Menu command ids are 1-based: TrackPopupMenuEx returns 0 for "dismissed", so
// 0 can't double as a real item. `ids[cmd - 1]` maps a command back to the
// Dart-side id.
void AppendItems(HMENU menu, const flutter::EncodableList& items,
                 std::vector<std::string>* ids) {
  for (const auto& entry : items) {
    const auto* item = std::get_if<flutter::EncodableMap>(&entry);
    if (item == nullptr) continue;

    const auto* id = Find(*item, "id");
    if (id == nullptr || !std::holds_alternative<std::string>(*id)) {
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }

    std::wstring label = Utf16(GetString(*item, "label"));
    UINT flags = MF_STRING;
    if (!GetBool(*item, "enabled", true)) flags |= MF_GRAYED;
    if (GetBool(*item, "checked", false)) flags |= MF_CHECKED;

    const auto* submenu = Find(*item, "submenu");
    if (submenu != nullptr &&
        std::holds_alternative<flutter::EncodableList>(*submenu)) {
      HMENU child = CreatePopupMenu();
      AppendItems(child, std::get<flutter::EncodableList>(*submenu), ids);
      // Destroyed along with the parent menu.
      AppendMenuW(menu, flags | MF_POPUP,
                  reinterpret_cast<UINT_PTR>(child), label.c_str());
      continue;
    }

    ids->push_back(std::get<std::string>(*id));
    AppendMenuW(menu, flags, static_cast<UINT_PTR>(ids->size()), label.c_str());
  }
}

}  // namespace

flutter::EncodableList GetDisplays() {
  struct Collector {
    flutter::EncodableList displays;
  } collector;

  // EnumDisplayMonitors is the only enumeration that reports the same monitor
  // set the window manager places windows on, including mirrored setups.
  auto callback = [](HMONITOR monitor, HDC, LPRECT, LPARAM data) -> BOOL {
    auto* collector = reinterpret_cast<Collector*>(data);

    MONITORINFOEXW info;
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info))
      return TRUE; // Skip this one, keep enumerating.

    // Per-monitor DPI, reported to Dart but NOT applied to the geometry below.
    //
    // Display coordinates have to be usable as `appWindow.position`, and on
    // Windows that property is raw device pixels: the getter is GetWindowRect
    // and the setter is SetWindowPos, neither of which scales (see
    // bitsdojo_window_windows/lib/src/window.dart). Dividing monitor rects by
    // the DPI here would leave the two in different units, so
    // `position = display.workArea.topLeft` landed at 2/3 of the intended
    // offset on a 150% display. Callers that want logical units have
    // scaleFactor to divide by.
    UINT dpi_x = 96;
    UINT dpi_y = 96;
    if (FAILED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
      dpi_x = 96;
      dpi_y = 96;
    }
    const double scale = dpi_x / 96.0;

    flutter::EncodableMap display;
    const std::string name = Utf8(info.szDevice);
    display[flutter::EncodableValue("id")] = flutter::EncodableValue(name);
    display[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
    display[flutter::EncodableValue("x")] =
        flutter::EncodableValue(static_cast<double>(info.rcMonitor.left));
    display[flutter::EncodableValue("y")] =
        flutter::EncodableValue(static_cast<double>(info.rcMonitor.top));
    display[flutter::EncodableValue("width")] = flutter::EncodableValue(
        static_cast<double>(info.rcMonitor.right - info.rcMonitor.left));
    display[flutter::EncodableValue("height")] = flutter::EncodableValue(
        static_cast<double>(info.rcMonitor.bottom - info.rcMonitor.top));
    display[flutter::EncodableValue("workX")] =
        flutter::EncodableValue(static_cast<double>(info.rcWork.left));
    display[flutter::EncodableValue("workY")] =
        flutter::EncodableValue(static_cast<double>(info.rcWork.top));
    display[flutter::EncodableValue("workWidth")] = flutter::EncodableValue(
        static_cast<double>(info.rcWork.right - info.rcWork.left));
    display[flutter::EncodableValue("workHeight")] = flutter::EncodableValue(
        static_cast<double>(info.rcWork.bottom - info.rcWork.top));
    display[flutter::EncodableValue("scaleFactor")] =
        flutter::EncodableValue(scale);
    display[flutter::EncodableValue("isPrimary")] =
        flutter::EncodableValue((info.dwFlags & MONITORINFOF_PRIMARY) != 0);

    collector->displays.push_back(flutter::EncodableValue(display));
    return TRUE;
  };

  EnumDisplayMonitors(nullptr, nullptr, callback,
                      reinterpret_cast<LPARAM>(&collector));
  return collector.displays;
}

int ShowAlert(HWND owner, const flutter::EncodableMap& args) {
  std::wstring title = Utf16(GetString(args, "title"));
  std::wstring message = Utf16(GetString(args, "message"));

  size_t button_count = 1;
  const auto* buttons = Find(args, "buttons");
  if (buttons != nullptr &&
      std::holds_alternative<flutter::EncodableList>(*buttons)) {
    button_count = std::get<flutter::EncodableList>(*buttons).size();
  }

  UINT flags = 0;
  switch (GetInt(args, "style", 0)) {
    case 1: flags |= MB_ICONWARNING; break;
    case 2: flags |= MB_ICONERROR; break;
    default: flags |= MB_ICONINFORMATION; break;
  }

  // ponytail: MessageBoxW only offers the fixed system button sets, so the
  // button COUNT picks the set and the caller's labels are dropped. Honouring
  // custom labels means TaskDialogIndirect, which needs the comctl32 v6
  // assembly in the runner's manifest - something the Flutter template doesn't
  // ship, so it would be a breaking ask of every host app. Upgrade there if
  // custom labels ever matter more than that.
  switch (button_count) {
    case 0:
    case 1: flags |= MB_OK; break;
    case 2: flags |= MB_OKCANCEL; break;
    default: flags |= MB_YESNOCANCEL; break;
  }

  // An empty body with only a caption reads as a bug; echo the title instead.
  int pressed = MessageBoxW(owner, message.empty() ? title.c_str()
                                                   : message.c_str(),
                            title.c_str(), flags);
  switch (pressed) {
    case IDOK:
    case IDYES:
      return 0;
    case IDNO:
      return 1;
    case IDCANCEL:
      // Cancel is last in both sets it appears in.
      return button_count >= 3 ? 2 : 1;
    default:
      return -1;
  }
}

std::string ShowMenu(HWND owner, HWND view, const flutter::EncodableMap& args) {
  const auto* items_value = Find(args, "items");
  if (items_value == nullptr ||
      !std::holds_alternative<flutter::EncodableList>(*items_value)) {
    return std::string();
  }
  const auto& items = std::get<flutter::EncodableList>(*items_value);
  if (items.empty()) return std::string();

  HMENU menu = CreatePopupMenu();
  std::vector<std::string> ids;
  AppendItems(menu, items, &ids);

  POINT point;
  auto x = GetDouble(args, "x");
  auto y = GetDouble(args, "y");
  HWND client = view != nullptr ? view : owner;
  if (x.has_value() && y.has_value() && client != nullptr) {
    // Dart sends logical pixels; the client area is physical.
    double scale = GetDpiForWindow(client) / 96.0;
    point.x = static_cast<LONG>(*x * scale);
    point.y = static_cast<LONG>(*y * scale);
    ClientToScreen(client, &point);
  } else {
    GetCursorPos(&point);
  }

  // Without the foreground activation the menu ignores the first click
  // outside itself instead of dismissing.
  if (owner != nullptr) SetForegroundWindow(owner);

  // TPM_RETURNCMD makes this call block until the menu closes and hand back
  // the chosen command instead of posting WM_COMMAND.
  UINT picked = TrackPopupMenuEx(
      menu,
      TPM_RETURNCMD | TPM_NONOTIFY | TPM_LEFTALIGN | TPM_TOPALIGN |
          TPM_RIGHTBUTTON,
      point.x, point.y, owner, nullptr);
  DestroyMenu(menu);  // Takes the submenus with it.

  if (picked == 0 || picked > ids.size()) return std::string();
  return ids[picked - 1];
}

}  // namespace bitsdojo_native_ui
