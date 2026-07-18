#include "bitsdojo_window.h"
#include "./bitsdojo_window_common.h"
#include "./include/bitsdojo_window_windows/bitsdojo_window_plugin.h"
#include "./window_util.h"
#include <dwmapi.h>
#include <math.h>
#include <windows.h>
#include <windowsx.h>

namespace bitsdojo_window {
UINT (*GetDpiForWindow)(HWND) = [](HWND) { return 96u; };
int (*GetSystemMetricsForDpi)(int, UINT) = [](int nIndex, UINT) {
  return GetSystemMetrics(nIndex);
};

struct WindowState {
  HWND flutter_child_window = nullptr;
  BOOL during_minimize = FALSE;
  BOOL during_maximize = FALSE;
  BOOL during_restore = FALSE;
  BOOL bypass_wm_size = FALSE;
  BOOL has_custom_frame = FALSE;
  BOOL visible_on_startup = TRUE;
  BOOL window_can_be_shown = FALSE;
  BOOL restore_by_moving = FALSE;
  BOOL during_size_move = FALSE;
  BOOL dpi_changed_during_size_move = FALSE;
  SIZE min_size = {0, 0};
  SIZE max_size = {0, 0};
  int window_cut_on_maximize = 0;
  int background_effect = 0;
  TCloseRequestedCallback closeRequestedCallback = nullptr;
};

const wchar_t *BDW_WINDOW_STATE = L"BDW_WindowState";

WindowState *getWindowState(HWND window) {
  if (window == nullptr)
    return nullptr;
  return (WindowState *)GetProp(window, BDW_WINDOW_STATE);
}

WindowState *getOrCreateWindowState(HWND window) {
  WindowState *state = getWindowState(window);
  if (state == nullptr) {
    state = new WindowState();
    SetProp(window, BDW_WINDOW_STATE, (HANDLE)state);
  }
  return state;
}

HWND flutter_window = nullptr; // Still keep global for getAppWindow() fallback
BOOL is_bitsdojo_window_loaded = FALSE;
BOOL is_dpi_aware = FALSE;
unsigned int global_flags = 0;

// Forward declarations
int init();
int getResizeMargin(HWND window);
void forceChildRefresh(HWND window);
void extendIntoClientArea(HWND hwnd);
LRESULT CALLBACK main_window_proc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam, UINT_PTR subclassID,
                                  DWORD_PTR refData);
LRESULT CALLBACK child_window_proc(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam, UINT_PTR subclassID,
                                   DWORD_PTR refData);
LRESULT handle_nchittest(HWND window, WPARAM wparam, LPARAM lparam);

auto bdw_init = init();

bool isBitsdojoWindowLoaded() { return is_bitsdojo_window_loaded; }

int init() {
  is_bitsdojo_window_loaded = true;
  if (auto user32 = LoadLibraryA("User32.dll")) {
    if (auto fn = GetProcAddress(user32, "GetDpiForWindow")) {
      is_dpi_aware = true;
      GetDpiForWindow = (decltype(GetDpiForWindow))fn;
      GetSystemMetricsForDpi = (decltype(GetSystemMetricsForDpi))GetProcAddress(
          user32, "GetSystemMetricsForDpi");
    }
  }
  return 1;
}

int configure(unsigned int flags) {
  global_flags = flags;
  return 1;
}

void attachMainWindow(HWND window) {
  if (window == nullptr) {
    return;
  }

  flutter_window = window;
  auto state = getOrCreateWindowState(window);
  state->has_custom_frame = (global_flags & BDW_CUSTOM_FRAME);
  state->visible_on_startup = !(global_flags & BDW_HIDE_ON_STARTUP);
  state->window_can_be_shown = state->visible_on_startup;

  auto style = GetWindowLongPtr(window, GWL_STYLE);
  style |= WS_CLIPCHILDREN | WS_THICKFRAME | WS_SIZEBOX | WS_MAXIMIZEBOX | WS_MINIMIZEBOX;
  SetWindowLongPtr(window, GWL_STYLE, style);

  SetProp(window, L"BitsDojoWindow", (HANDLE)(1));
  SetWindowSubclass(window, main_window_proc, 1, NULL);

  if (state->has_custom_frame == TRUE) {
    extendIntoClientArea(window);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_DRAWFRAME);
  }
}

void attachFlutterChildWindow(HWND parent, HWND child) {
  if (parent == nullptr || child == nullptr) {
    return;
  }

  auto state = getOrCreateWindowState(parent);
  state->flutter_child_window = child;
  SetWindowSubclass(child, child_window_proc, 1, NULL);
  forceChildRefresh(parent);
}

void setWindowCutOnMaximize(HWND window, int value) {
  getOrCreateWindowState(window)->window_cut_on_maximize = value;
}

void setMinSize(HWND window, int width, int height) {
  auto state = getOrCreateWindowState(window);
  state->min_size.cx = width;
  state->min_size.cy = height;
}

void setMaxSize(HWND window, int width, int height) {
  auto state = getOrCreateWindowState(window);
  state->max_size.cx = width;
  state->max_size.cy = height;
}

void setWindowCanBeShown(HWND window, bool value) {
  getOrCreateWindowState(window)->window_can_be_shown = value;
}

HWND getAppWindow() { return flutter_window; }

bool isDPIAware() { return is_dpi_aware; }

LRESULT CALLBACK main_window_proc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam, UINT_PTR subclassID,
                                  DWORD_PTR refData);

LRESULT handle_nchittest(HWND window, WPARAM wparam, LPARAM lparam);

LRESULT CALLBACK child_window_proc(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam, UINT_PTR subclassID,
                                   DWORD_PTR refData) {
  if (message == WM_NCHITTEST) {
    HWND parent = GetParent(window);
    auto state = getWindowState(parent);
    if (state && state->has_custom_frame == TRUE) {
      LRESULT result = handle_nchittest(parent, wparam, lparam);
      if (result != HTCLIENT) {
        return HTTRANSPARENT; // Let the parent window handle it
      }
    }
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

void forceChildRefresh(HWND window) {
  auto state = getWindowState(window);
  if (!state || state->flutter_child_window == nullptr)
    return;

  RECT rc;
  GetClientRect(window, &rc);
  int inset = 0;
  int width = max(0, (rc.right - rc.left));
  int height = max(0, (rc.bottom - rc.top));
  SetWindowPos(state->flutter_child_window, 0, inset, inset, width, height,
               SWP_NOACTIVATE);
}

int getResizeMargin(HWND window) {
  UINT currentDpi = GetDpiForWindow(window);
  int resizeBorder = GetSystemMetricsForDpi(SM_CXSIZEFRAME, currentDpi);
  int borderPadding = GetSystemMetricsForDpi(SM_CXPADDEDBORDER, currentDpi);
  int minimumInteractiveMargin = max(8, static_cast<int>(ceil(6.0 * currentDpi / 96.0)));
  bool isMaximized = IsZoomed(window);
  if (isMaximized) {
    return max(borderPadding, minimumInteractiveMargin);
  }
  return max(resizeBorder + borderPadding, minimumInteractiveMargin);
}

void extendIntoClientArea(HWND hwnd) {
  MARGINS margins = {0, 0, 0, 0};
  DwmExtendFrameIntoClientArea(hwnd, &margins);
}

LRESULT handle_nchittest(HWND window, WPARAM wparam, LPARAM lparam) {
  bool isMaximized = IsZoomed(window);
  if (isMaximized)
    return HTCLIENT;
  POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  ScreenToClient(window, &pt);
  RECT rc;
  GetClientRect(window, &rc);
  int resizeMargin = getResizeMargin(window);
  if (pt.y < resizeMargin) {
    if (pt.x < resizeMargin) {
      return HTTOPLEFT;
    }
    if (pt.x > (rc.right - resizeMargin)) {
      return HTTOPRIGHT;
    }
    return HTTOP;
  }
  if (pt.y > (rc.bottom - resizeMargin)) {
    if (pt.x < resizeMargin) {
      return HTBOTTOMLEFT;
    }
    if (pt.x > (rc.right - resizeMargin)) {
      return HTBOTTOMRIGHT;
    }
    return HTBOTTOM;
  }
  if (pt.x < resizeMargin) {
    return HTLEFT;
  }
  if (pt.x > (rc.right - resizeMargin)) {
    return HTRIGHT;
  }
  return HTCLIENT;
}

RECT getScreenRectForWindow(HWND window) {
  MONITORINFO monitorInfo = {};
  monitorInfo.cbSize = DWORD(sizeof(MONITORINFO));
  auto monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  GetMonitorInfoW(monitor, static_cast<LPMONITORINFO>(&monitorInfo));
  return monitorInfo.rcMonitor;
}

RECT getWorkingScreenRectForWindow(HWND window) {
  MONITORINFO monitorInfo = {};
  monitorInfo.cbSize = DWORD(sizeof(MONITORINFO));
  auto monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  GetMonitorInfoW(monitor, static_cast<LPMONITORINFO>(&monitorInfo));
  return monitorInfo.rcWork;
}

void adjustPositionOnRestoreByMove(HWND window, WindowState *state,
                                   WINDOWPOS *winPos) {
  if (state->restore_by_moving == FALSE)
    return;

  auto screenRect = getWorkingScreenRectForWindow(window);

  if (winPos->y < screenRect.top) {
    winPos->y = screenRect.top;
  }
}

void adjustMaximizedSize(HWND window, WINDOWPOS *winPos) {
  auto screenRect = getWorkingScreenRectForWindow(window);
  if ((winPos->x < screenRect.left) && (winPos->y < screenRect.top) &&
      (winPos->cx > (screenRect.right - screenRect.left)) &&
      (winPos->cy > (screenRect.bottom - screenRect.top))) {
    winPos->x = screenRect.left;
    winPos->y = screenRect.top;
    winPos->cx = screenRect.right - screenRect.left;
    winPos->cy = screenRect.bottom - screenRect.top;
  }
}

void adjustMaximizedRects(HWND window, NCCALCSIZE_PARAMS *params) {
  auto screenRect = getWorkingScreenRectForWindow(window);
  for (int i = 0; i < 3; i++) {
    if ((params->rgrc[i].left < screenRect.left) &&
        (params->rgrc[i].top < screenRect.top) &&
        (params->rgrc[i].right > screenRect.right) &&
        (params->rgrc[i].bottom > screenRect.bottom)) {
      params->rgrc[i].left = screenRect.left;
      params->rgrc[i].top = screenRect.top;
      params->rgrc[i].right = screenRect.right;
      params->rgrc[i].bottom = screenRect.bottom;
    }
  }
}

double getScaleFactor(HWND window) {
  UINT dpi = GetDpiForWindow(window);
  return dpi / 96.0;
}

LRESULT handle_nccalcsize(HWND window, WPARAM wparam, LPARAM lparam) {
  if (!wparam) {
    return 0;
  }

  auto params = reinterpret_cast<NCCALCSIZE_PARAMS *>(lparam);
  if (params->lppos)
    adjustMaximizedSize(window, params->lppos);
  adjustMaximizedRects(window, params);

  auto initialRect = params->rgrc[0];
  auto defaultResult = DefSubclassProc(window, WM_NCCALCSIZE, wparam, lparam);

  if (defaultResult != 0) {
    return defaultResult;
  }

  bool isMaximized = IsZoomed(window);
  params->rgrc[0] = initialRect;
  double scaleFactor = getScaleFactor(window);
  int scaleFactorInt = (int)ceil(scaleFactor);

  auto state = getWindowState(window);
  int window_cut = state ? state->window_cut_on_maximize : 0;

  if (isMaximized) {
    int sidesCut = (int)ceil(scaleFactor * window_cut);
    int topCut = (int)ceil(scaleFactor * window_cut) + scaleFactorInt + 1;

    params->rgrc[0].top -= topCut;
    params->rgrc[0].left -= sidesCut;
    params->rgrc[0].right += sidesCut;
    params->rgrc[0].bottom += sidesCut;
  } else if (state &&
             (state->background_effect == 0 || state->background_effect == 1)) {
    // Hide borders for Disabled/Transparent (Flat look)
    params->rgrc[0].top -= 1;
    params->rgrc[0].left -= 1;
    params->rgrc[0].right += 1;
    params->rgrc[0].bottom += 1;
  } else {
    // Show system borders for Acrylic/Mica etc. (3D look)
    params->rgrc[0].top -= 1;
  }

  return 0;
}

void adjustChildWindowSize(HWND window) {
  auto state = getWindowState(window);
  if (!state || state->flutter_child_window == nullptr)
    return;
  RECT clientRect;
  GetClientRect(window, &clientRect);
  int inset = 0;
  int width = max(0, (clientRect.right - clientRect.left));
  int height = max(0, (clientRect.bottom - clientRect.top));
  SetWindowPos(state->flutter_child_window, 0, inset, inset, width, height,
               SWP_NOACTIVATE);
}

bool centerOnMonitorContainingMouse(HWND window, int width, int height) {
  MONITORINFO monitorInfo = {};
  monitorInfo.cbSize = DWORD(sizeof(MONITORINFO));

  POINT mousePosition;
  if (GetCursorPos(&mousePosition) == FALSE) {
    return false;
  }
  auto monitor = MonitorFromPoint(mousePosition, MONITOR_DEFAULTTONEAREST);
  if (GetMonitorInfoW(monitor, static_cast<LPMONITORINFO>(&monitorInfo)) ==
      FALSE) {
    return false;
  }
  auto monitorWidth = monitorInfo.rcWork.right - monitorInfo.rcWork.left;
  auto monitorHeight = monitorInfo.rcWork.bottom - monitorInfo.rcWork.top;
  auto x = (monitorWidth - width) / 2;
  auto y = (monitorHeight - height) / 2;
  x += monitorInfo.rcWork.left;
  y += monitorInfo.rcWork.top;
  SetWindowPos(window, 0, x, y, 0, 0,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOSIZE);
  return true;
}

void handle_bdw_action(HWND window, WPARAM action, LPARAM actionData) {
  switch (action) {
  case BDW_SETWINDOWPOS: {
    auto param = (SWPParam *)(actionData);
    SetWindowPos(window, 0, param->x, param->y, param->cx, param->cy,
                 param->uFlags);
    HeapFree(GetProcessHeap(), 0, param);
    break;
  }
  case BDW_SETWINDOWTEXT: {
    auto param = (SWTParam *)(actionData);
    SetWindowText(window, param->text);
    HeapFree(GetProcessHeap(), 0, (LPVOID)param->text);
    HeapFree(GetProcessHeap(), 0, param);
    break;
  }
  case BDW_FORCECHILDREFRESH: {
    forceChildRefresh(window);
    break;
  }
  }
}

void setCloseRequestedCallback(HWND window, TCloseRequestedCallback callback) {
  auto state = getOrCreateWindowState(window);
  state->closeRequestedCallback = callback;
}

LRESULT CALLBACK main_window_proc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam, UINT_PTR sublssID,
                                  DWORD_PTR refData) {
  auto state = getOrCreateWindowState(window);
  switch (message) {
  case WM_ERASEBKGND: {
    return 1;
  }
  case WM_NCCREATE: {
    break;
  }
  case WM_NCHITTEST: {
    if (state->has_custom_frame == FALSE) {
      break;
    }
    return handle_nchittest(window, wparam, lparam);
  }
  case WM_NCCALCSIZE: {
    if (state->has_custom_frame == FALSE) {
      break;
    }
    return handle_nccalcsize(window, wparam, lparam);
  }
  case WM_CREATE: {
    auto createStruct = reinterpret_cast<CREATESTRUCT *>(lparam);
    LRESULT result = DefSubclassProc(window, message, wparam, lparam);
    if (state->has_custom_frame == TRUE) {
      extendIntoClientArea(window);
      SetWindowPos(window, nullptr, 0, 0, 0, 0,
                   SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_DRAWFRAME);
    }
    centerOnMonitorContainingMouse(window, createStruct->cx, createStruct->cy);
    if (state->visible_on_startup == TRUE) {
      state->window_can_be_shown = TRUE;
      forceChildRefresh(window);
    }
    return result;
  }
  case WM_DPICHANGED: {
    if (state->during_size_move == TRUE) {
      state->dpi_changed_during_size_move = TRUE;
    }
    forceChildRefresh(window);
    break;
  }
  case WM_SIZE: {
    if (state->during_minimize == TRUE) {
      return 0;
    }
    if (state->bypass_wm_size == TRUE) {
      return DefWindowProc(window, message, wparam, lparam);
    }
    break;
  }
  case WM_SYSCOMMAND: {
    if (wparam == SC_MINIMIZE) {
      state->during_minimize = TRUE;
    }
    if (wparam == SC_MAXIMIZE) {
      state->during_maximize = TRUE;
    }
    if (wparam == SC_RESTORE) {
      state->during_restore = TRUE;
    }
    LRESULT result = DefSubclassProc(window, message, wparam, lparam);
    state->during_minimize = FALSE;
    state->during_maximize = FALSE;
    state->during_restore = FALSE;
    return result;
  }
  case WM_WINDOWPOSCHANGING: {
    auto winPos = reinterpret_cast<WINDOWPOS *>(lparam);
    bool isResize = !(winPos->flags & SWP_NOSIZE);
    if (state->has_custom_frame && isResize) {
      adjustMaximizedSize(window, winPos);
      adjustPositionOnRestoreByMove(window, state, winPos);
    }
    BOOL isShowWindow = ((winPos->flags & SWP_SHOWWINDOW) == SWP_SHOWWINDOW);

    if ((isShowWindow == TRUE) && (state->window_can_be_shown == FALSE) &&
        (state->visible_on_startup == FALSE)) {
      winPos->flags &= ~SWP_SHOWWINDOW;
    }

    break;
  }
  case WM_WINDOWPOSCHANGED: {
    auto winPos = reinterpret_cast<WINDOWPOS *>(lparam);
    bool isResize = !(winPos->flags & SWP_NOSIZE);
    if (state->has_custom_frame && isResize) {

      adjustMaximizedSize(window, winPos);
      adjustPositionOnRestoreByMove(window, state, winPos);
    }

    if (false == state->window_can_be_shown) {
      break;
    }

    if (state->bypass_wm_size == TRUE) {
      if (isResize && (!state->during_minimize) && (winPos->cx != 0)) {
        adjustChildWindowSize(window);
      }
    }
    break;
  }
  case WM_GETMINMAXINFO: {
    auto info = reinterpret_cast<MINMAXINFO *>(lparam);
    if ((state->min_size.cx != 0) && (state->min_size.cy != 0)) {
      SIZE minSize = state->min_size;
      UINT dpi = GetDpiForWindow(window);
      double scale_factor = dpi / 96.0;
      minSize.cx = static_cast<int>(minSize.cx * scale_factor);
      minSize.cy = static_cast<int>(minSize.cy * scale_factor);
      info->ptMinTrackSize.x = minSize.cx;
      info->ptMinTrackSize.y = minSize.cy;
    }
    if ((state->max_size.cx != 0) && (state->max_size.cy != 0)) {
      SIZE maxSize = state->max_size;
      UINT dpi = GetDpiForWindow(window);
      double scale_factor = dpi / 96.0;
      maxSize.cx = static_cast<int>(maxSize.cx * scale_factor);
      maxSize.cy = static_cast<int>(maxSize.cy * scale_factor);
      info->ptMaxTrackSize.x = maxSize.cx;
      info->ptMaxTrackSize.y = maxSize.cy;
    }
    return 0;
  }
  case WM_ENTERSIZEMOVE: {
    bool isMaximized = IsZoomed(window);
    state->during_size_move = TRUE;
    if (isMaximized) {
      state->restore_by_moving = TRUE;
    }
    break;
  }
  case WM_EXITSIZEMOVE: {
    state->during_size_move = FALSE;
    if (state->dpi_changed_during_size_move) {
      forceChildRefresh(window);
    }
    state->dpi_changed_during_size_move = FALSE;
    state->restore_by_moving = FALSE;
    break;
  }
  case WM_CLOSE: {
    if (state->closeRequestedCallback) {
      state->closeRequestedCallback(window);
      return 0; // Prevent close
    }
    break;
  }
  case WM_BDW_ACTION: {
    handle_bdw_action(window, wparam, lparam);
    break;
  }
  case WM_NCDESTROY: {
    if (state) {
      RemoveProp(window, BDW_WINDOW_STATE);
      delete state;
    }
    break;
  }
  default:
    break;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

bool dragAppWindow(HWND window) {
  if (window == nullptr) {
    return false;
  }
  ReleaseCapture();
  SendMessage(window, WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
  return true;
}

bool isAlwaysOnTop(HWND window) {
  auto dwExStyle = GetWindowLongPtr(window, GWL_EXSTYLE);
  return (dwExStyle & WS_EX_TOPMOST) != 0;
}

void setAlwaysOnTop(HWND window, int value) {
  RECT rc;
  GetClientRect(window, &rc);
  int width = rc.right - rc.left;
  int height = rc.bottom - rc.top;
  SetWindowPos(window, value == 1 ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, width,
               height, SWP_NOMOVE | SWP_NOACTIVATE);
}

void setBackgroundEffect(HWND window, int effect) {
  if (window == nullptr)
    return;

  auto state = getWindowState(window);
  if (state) {
    state->background_effect = effect;
  }

  // Windows 11 system backdrop support
  HMODULE hUser32 = GetModuleHandleA("user32.dll");
  typedef BOOL(WINAPI * pSetWindowCompositionAttribute)(HWND, void *);
  pSetWindowCompositionAttribute setWindowCompositionAttribute =
      (pSetWindowCompositionAttribute)GetProcAddress(
          hUser32, "SetWindowCompositionAttribute");

  // -----------------------------
  // Backdrop mapping
  // -----------------------------
  DWORD dwBackdropType = 1; // DWMSBT_NONE
  if (effect == 2)
    dwBackdropType = 3; // DWMSBT_TRANSIENTWINDOW (Acrylic)
  if (effect == 3)
    dwBackdropType = 2; // DWMSBT_MAINWINDOW (Mica)
  if (effect == 4)
    dwBackdropType = 4; // DWMSBT_TABBEDWINDOW (Tabbed)

  // -----------------------------
  // Background brush
  // -----------------------------
  if (effect != 0 || setWindowCompositionAttribute) {
    // Prevent Win32 from painting background
    SetClassLongPtr(window, GCLP_HBRBACKGROUND,
                    (LONG_PTR)GetStockObject(NULL_BRUSH));
    if (state && state->flutter_child_window) {
      SetClassLongPtr(state->flutter_child_window, GCLP_HBRBACKGROUND,
                      (LONG_PTR)GetStockObject(NULL_BRUSH));
    }
  } else {
    // Restore default brush
    SetClassLongPtr(window, GCLP_HBRBACKGROUND,
                    (LONG_PTR)GetStockObject(WHITE_BRUSH));
  }

  // -----------------------------
  // Effect handling
  // -----------------------------
  if (effect >= 2) {
    // Acrylic / Mica / Tabbed (Windows 11 system backdrop)
    DwmSetWindowAttribute(window, 38, &dwBackdropType, sizeof(dwBackdropType));

    if (effect == 2 && setWindowCompositionAttribute) {
      // Acrylic also needs AccentPolicy
      struct ACCENT_POLICY {
        int AccentState;
        int AccentFlags;
        int GradientColor;
        int AnimationId;
      };
      struct WINDOWCOMPOSITIONATTRIBDATA {
        int Attrib;
        void *pvData;
        int cbData;
      };

      ACCENT_POLICY policy = {4 /* ACCENT_ENABLE_ACRYLICBLURBEHIND */, 2,
                              0x00FFFFFF, 0};

      WINDOWCOMPOSITIONATTRIBDATA data = {19 /* WCA_ACCENT_POLICY */, &policy,
                                          sizeof(policy)};

      setWindowCompositionAttribute(window, &data);
    }
  } else {
    // -----------------------------
    // Disabled / Transparent (TRUE alpha blending transparency)
    // -----------------------------

    // 1️⃣ Disable all DWM backdrops
    DWORD none = 1; // DWMSBT_NONE
    DwmSetWindowAttribute(window, 38, &none, sizeof(none));

    // 2️⃣ Enable Transparent Gradient policy (State 2)
    if (setWindowCompositionAttribute) {
      struct ACCENT_POLICY {
        int AccentState;
        int AccentFlags;
        int GradientColor;
        int AnimationId;
      };
      struct WINDOWCOMPOSITIONATTRIBDATA {
        int Attrib;
        void *pvData;
        int cbData;
      };

      // ACCENT_ENABLE_TRANSPARENT_GRADIENT (2) allows true per-pixel alpha
      // blending without using a ColorKey (which creates "holes")
      ACCENT_POLICY policy = {2 /* ACCENT_ENABLE_TRANSPARENT_GRADIENT */, 2, 0,
                              0};

      WINDOWCOMPOSITIONATTRIBDATA data = {19 /* WCA_ACCENT_POLICY */, &policy,
                                          sizeof(policy)};

      setWindowCompositionAttribute(window, &data);
    } else {
      // 3️⃣ Fallback to layered window + color key ONLY if modern API is
      // unavailable
      LONG exStyle = GetWindowLong(window, GWL_EXSTYLE);
      SetWindowLong(window, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);
      // Black = transparent (Known issue: black pixels in UI will be holes)
      SetLayeredWindowAttributes(window, RGB(0, 0, 0), 255, LWA_COLORKEY);
    }
  }

  // -----------------------------
  // Force refresh
  // -----------------------------
  SetWindowPos(window, NULL, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOACTIVATE);
}

} // namespace bitsdojo_window

int bitsdojo_window_configure(unsigned int flags) {
  return bitsdojo_window::configure(flags);
}
