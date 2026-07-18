#ifndef BITSDOJO_WINDOW_H_
#define BITSDOJO_WINDOW_H_
#include <windows.h>

namespace bitsdojo_window {
typedef bool (*TIsBitsdojoWindowLoaded)();
bool isBitsdojoWindowLoaded();

void attachMainWindow(HWND window);
void attachFlutterChildWindow(HWND parent, HWND child);

typedef void (*TSetWindowCanBeShown)(HWND, bool);
void setWindowCanBeShown(HWND window, bool value);

typedef bool (*TDragAppWindow)(HWND);
bool dragAppWindow(HWND window);

typedef HWND (*TGetAppWindow)();
HWND getAppWindow();

typedef void (*TSetMinSize)(HWND, int, int);
void setMinSize(HWND window, int width, int height);

typedef void (*TSetMaxSize)(HWND, int, int);
void setMaxSize(HWND window, int width, int height);

typedef void (*TSetWindowCutOnMaximize)(HWND, int);
void setWindowCutOnMaximize(HWND window, int value);

typedef bool (*TIsDPIAware)();
bool isDPIAware();

typedef bool (*TIsAlwaysOnTop)(HWND);
bool isAlwaysOnTop(HWND window);

typedef void (*TSetAlwaysOnTop)(HWND, int);
void setAlwaysOnTop(HWND window, int value);

typedef void (*TCloseRequestedCallback)(HWND);
typedef void (*TSetCloseRequestedCallback)(HWND, TCloseRequestedCallback);
void setCloseRequestedCallback(HWND window, TCloseRequestedCallback callback);

typedef void (*TSetBackgroundEffect)(HWND, int);
void setBackgroundEffect(HWND window, int effect);

} // namespace bitsdojo_window
#endif
