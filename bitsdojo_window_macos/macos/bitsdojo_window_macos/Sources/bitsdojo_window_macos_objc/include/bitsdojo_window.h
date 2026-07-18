#ifndef bitsdojo_window_h
#define bitsdojo_window_h

#include "./bitsdojo_window_common.h"
#import <Cocoa/Cocoa.h>

// Native private API

typedef bool (*TWindowCanBeShown)(NSWindow *);
bool windowCanBeShown(NSWindow *window);

typedef bool (*TAppWindowIsSet)();
bool appWindowIsSet();

typedef void (*TSetAppWindow)(NSWindow *);
void setAppWindow(NSWindow *window);

// Public API

typedef NSWindow *(*TGetAppWindow)();
NSWindow *getAppWindow();

typedef void (*TSetWindowCanBeShown)(NSWindow *, bool);
void setWindowCanBeShown(NSWindow *window, bool value);

typedef void (*TSetInsideDoWhenWindowReady)(bool);
void setInsideDoWhenWindowReady(bool value);

typedef void (*TShowWindow)(NSWindow *);
void showWindow(NSWindow *window);

typedef void (*THideWindow)(NSWindow *);
void hideWindow(NSWindow *window);

typedef void (*TMoveWindow)(NSWindow *);
void moveWindow(NSWindow *window);

typedef void (*TSetSize)(NSWindow *, int, int);
void setSize(NSWindow *window, int width, int height);

typedef void (*TSetMinSize)(NSWindow *, int, int);
void setMinSize(NSWindow *window, int width, int height);

typedef void (*TSetMaxSize)(NSWindow *, int, int);
void setMaxSize(NSWindow *window, int width, int height);

typedef BDWStatus (*TGetScreenInfoForWindow)(NSWindow *, BDWScreenInfo *);
BDWStatus getScreenInfoForWindow(NSWindow *, BDWScreenInfo *);

typedef BDWStatus (*TSetPositionForWindow)(NSWindow *, BDWOffset *);
BDWStatus setPositionForWindow(NSWindow *, BDWOffset *);

typedef BDWStatus (*TSetRectForWindow)(NSWindow *, BDWRect *);
BDWStatus setRectForWindow(NSWindow *, BDWRect *);

typedef BDWStatus (*TGetRectForWindow)(NSWindow *, BDWRect *);
BDWStatus getRectForWindow(NSWindow *, BDWRect *);

typedef bool (*TIsWindowVisible)(NSWindow *window);
bool isWindowVisible(NSWindow *window);

typedef bool (*TIsWindowMaximized)(NSWindow *window);
bool isWindowMaximized(NSWindow *window);

typedef void (*TMaximizeOrRestoreWindow)(NSWindow *);
void maximizeOrRestoreWindow(NSWindow *window);

typedef void (*TMaximizeWindow)(NSWindow *);
void maximizeWindow(NSWindow *window);

typedef void (*TToggleFullScreen)(NSWindow *);
void toggleFullScreen(NSWindow *window);

typedef void (*TMinimizeWindow)(NSWindow *);
void minimizeWindow(NSWindow *window);

typedef void (*TCloseWindow)(NSWindow *);
void closeWindow(NSWindow *window);

typedef void (*TSetWindowTitle)(NSWindow *, const char *);
void setWindowTitle(NSWindow *window, const char *title);

typedef double (*TGetTitleBarHeight)(NSWindow *);
double getTitleBarHeight(NSWindow *window);

typedef BDWStatus (*TGetTitleBarButtonSize)(NSWindow *, BDWOffset *);
BDWStatus getTitleBarButtonSize(NSWindow *window, BDWOffset *size);

typedef double (*TGetWindowScaleFactor)(NSWindow *);
double getWindowScaleFactor(NSWindow *window);

typedef void (*TSetAlwaysOnTop)(NSWindow *, int);
void setAlwaysOnTop(NSWindow *window, int value);

typedef bool (*TIsAlwaysOnTop)(NSWindow *);
bool isAlwaysOnTop(NSWindow *window);

typedef void (*TSetBackgroundEffect)(NSWindow *, int);
void setBackgroundEffect(NSWindow *window, int effect);

typedef void (*TSetTitleBarHeight)(NSWindow *, int);
void setTitleBarHeight(NSWindow *window, int height);

typedef bool (*TIsPrimaryWindow)(NSWindow *);
bool isPrimaryWindow(NSWindow *window);

typedef void (*TTerminateApp)();
void terminateApp();

typedef void (*TSetWindowButtonVisibility)(NSWindow *, int, bool);
void setWindowButtonVisibility(NSWindow *window, int button, bool visible);

typedef void (*TSetWindowButtonOffset)(NSWindow *, int, double, double);
void setWindowButtonOffset(NSWindow *window, int button, double x, double y);

typedef void (*TSetHasShadow)(NSWindow *, int);
BDW_EXPORT void setHasShadow(NSWindow *window, int value);

typedef bool (*TIsHasShadow)(NSWindow *);
BDW_EXPORT bool isHasShadow(NSWindow *window);

#endif /* bitsdojo_window_h */
