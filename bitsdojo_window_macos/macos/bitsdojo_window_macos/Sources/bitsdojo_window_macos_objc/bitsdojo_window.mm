#import "bitsdojo_window.h"
#import "bitsdojo_window_controller.h"
#import "titlebar_button_manager.h"
#include <Cocoa/Cocoa.h>

NSMapTable<NSWindow *, BitsdojoWindowController *> *_windowControllers = nil;
NSWindow *_primaryWindow = nil;

bool _insideDoWhenWindowReady = false;

void setInsideDoWhenWindowReady(bool value) {
  _insideDoWhenWindowReady = value;
}

bool appWindowIsSet() {
  return _windowControllers != nil && _windowControllers.count > 0;
}

void setAppWindow(NSWindow *value) {
  if (_windowControllers == nil) {
    _windowControllers = [NSMapTable weakToStrongObjectsMapTable];
  }
  if (_primaryWindow == nil) {
    _primaryWindow = value;
  }
  if ([_windowControllers objectForKey:value] == nil) {
    BitsdojoWindowController *controller =
        [[BitsdojoWindowController alloc] initWithWindow:value];
    [_windowControllers setObject:controller forKey:value];
  }
}

#ifdef __cplusplus
extern "C" {
#endif
BitsdojoWindowController *getControllerForWindow(NSWindow *window) {
  if (window == nil)
    return nil;
  return [_windowControllers objectForKey:window];
}
#ifdef __cplusplus
}
#endif

NSWindow *getAppWindow() {
  // If we only have one registered window, return it.
  if (_windowControllers != nil && _windowControllers.count == 1) {
    return _windowControllers.keyEnumerator.nextObject;
  }
  // If we have multiple windows, returning _primaryWindow is dangerous
  // because child windows call this before they have their own handle.
  // We return nil to signal that the handle is not yet associated with the
  // calling engine. Dart side will then wait for the 'windowReady'
  // MethodChannel message.
  return nil;
}

bool windowCanBeShown(NSWindow *window) {
  BitsdojoWindowController *controller = getControllerForWindow(window);
  if (controller == nil)
    return false; // Default to false if no controller to prevent flicker
  return controller.canBeShown;
}

void setWindowCanBeShown(NSWindow *window, bool value) {
  BitsdojoWindowController *controller = getControllerForWindow(window);
  if (controller != nil) {
    controller.canBeShown = value;
  }
}
void runOnMainThread(dispatch_block_t block) {
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_async(dispatch_get_main_queue(), block);
  }
}

void showWindow(NSWindow *window) {
  setWindowCanBeShown(window, true);
  runOnMainThread(^{
    if (![[NSApplication sharedApplication] isActive]) {
      [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    }
    [window setAlphaValue:1.0];
    [window makeKeyAndOrderFront:nil];
  });
}

void hideWindow(NSWindow *window) {
  runOnMainThread(^{
    [window setIsVisible:FALSE];
  });
}

void moveWindow(NSWindow *window) {
  runOnMainThread(^{
    // PATCH(vidra): only start a window drag while the left mouse button is
    // ACTUALLY still held. appWindow.startDragging() hops Dart -> platform
    // channel -> here asynchronously, so on a quick click-with-drift (e.g.
    // tapping a control that overlaps a MoveWindow region) the button is
    // often already released by the time this runs. [window currentEvent] can
    // still report a *stale* LeftMouseDragged, and performWindowDragWithEvent:
    // with an event whose mouse-up already fired wedges AppKit's drag session
    // waiting for a mouse-up that never comes — the window then swallows ALL
    // mouse input until the next real click (reported as "click does nothing,
    // next click works"). -[NSEvent pressedMouseButtons] is a live hardware
    // query, immune to the stale-currentEvent race, so it closes the window
    // the type check alone can't.
    if (([NSEvent pressedMouseButtons] & 0x1) == 0) {
      return;
    }
    NSEvent *event = [window currentEvent];
    if (event == nil) {
      return;
    }
    if (event.type != NSEventTypeLeftMouseDown &&
        event.type != NSEventTypeLeftMouseDragged) {
      return;
    }
    [window performWindowDragWithEvent:event];
  });
}

void setSize(NSWindow *window, int width, int height) {
  NSRect frame = [window frame];
  frame.size.width = width;
  frame.size.height = height;
  dispatch_async(dispatch_get_main_queue(), ^{
    [window setFrame:frame display:true];
  });
}

void setMinSize(NSWindow *window, int width, int height) {
  NSSize minSize;
  minSize.width = width;
  minSize.height = height;
  runOnMainThread(^{
    [window setMinSize:minSize];
  });
}

void setMaxSize(NSWindow *window, int width, int height) {
  NSSize maxSize;
  if (width < 0 || height < 0) {
    maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
  } else {
    maxSize.width = width;
    maxSize.height = height;
  }
  runOnMainThread(^{
    [window setMaxSize:maxSize];
  });
}

BDWStatus getScreenInfoForWindow(NSWindow *window, BDWScreenInfo *screenInfo) {
  BitsdojoWindowController *controller = getControllerForWindow(window);
  if (controller == nil) {
    return BDW_FAILED;
  }
  auto workingScreenRect = controller.workingScreenRect;
  auto fullScreenRect = controller.fullScreenRect;
  auto menuBarHeight =
      (fullScreenRect.origin.y + fullScreenRect.size.height) -
      (workingScreenRect.origin.y + workingScreenRect.size.height);
  BDWRect *workingRect = screenInfo->workingRect;
  BDWRect *fullRect = screenInfo->fullRect;
  workingRect->top = menuBarHeight;
  workingRect->left = workingScreenRect.origin.x - fullScreenRect.origin.x;
  workingRect->bottom = workingRect->top + workingScreenRect.size.height;
  workingRect->right = workingRect->left + workingScreenRect.size.width;
  fullRect->left = 0;
  fullRect->right = fullScreenRect.size.width;
  fullRect->top = 0;
  fullRect->bottom = fullScreenRect.size.height;
  return BDW_SUCCESS;
}

BDWStatus setPositionForWindow(NSWindow *window, BDWOffset *offset) {
  runOnMainThread(^{
    NSPoint position;
    auto screen = [window screen];
    auto fullScreenRect = [screen frame];
    position.x = fullScreenRect.origin.x + offset->x;
    position.y =
        fullScreenRect.origin.y + fullScreenRect.size.height - offset->y;
    dispatch_async(dispatch_get_main_queue(), ^{
      [window setFrameTopLeftPoint:position];
    });
  });
  return BDW_SUCCESS;
}

BDWStatus setRectForWindow(NSWindow *window, BDWRect *rect) {
  BitsdojoWindowController *controller = getControllerForWindow(window);

  if (controller == nil) {
    return BDW_FAILED;
  }
  NSRect fullScreenRect = controller.fullScreenRect;
  NSRect frame;
  frame.size.width = rect->right - rect->left;
  frame.size.height = rect->bottom - rect->top;
  frame.origin.x = fullScreenRect.origin.x + rect->left;
  frame.origin.y =
      fullScreenRect.origin.y + fullScreenRect.size.height - rect->bottom;
  controller.windowFrame = frame;
  dispatch_async(dispatch_get_main_queue(), ^{
    [window setFrame:frame display:YES];
  });
  return BDW_SUCCESS;
}

BDWStatus getRectForWindow(NSWindow *window, BDWRect *rect) {
  BitsdojoWindowController *controller = getControllerForWindow(window);
  if (controller == nil) {
    return BDW_FAILED;
  }
  auto workingScreenRect = controller.workingScreenRect;
  NSRect frame = controller.windowFrame;
  NSRect fullScreenRect = controller.fullScreenRect;
  rect->left = frame.origin.x - fullScreenRect.origin.x;
  auto frameTop = frame.origin.y + frame.size.height;
  auto workingScreenTop =
      workingScreenRect.origin.y + workingScreenRect.size.height;
  rect->top = workingScreenTop - frameTop;
  rect->right = rect->left + frame.size.width;
  rect->bottom = rect->top + frame.size.height;
  return BDW_SUCCESS;
}

bool isWindowMaximized(NSWindow *window) {
  BitsdojoWindowController *controller = getControllerForWindow(window);
  if (controller == nil)
    return false;
  return controller.isZoomed;
}

bool isWindowVisible(NSWindow *window) {
  BitsdojoWindowController *controller = getControllerForWindow(window);
  if (controller == nil)
    return false;
  return controller.isVisible;
}

void maximizeOrRestoreWindow(NSWindow *window) {
  runOnMainThread(^{
    [window zoom:nil];
  });
}

void maximizeWindow(NSWindow *window) {
  runOnMainThread(^{
    auto screen = [window screen];
    [window setFrame:[screen visibleFrame] display:true animate:true];
  });
}

void toggleFullScreen(NSWindow *window) {
  runOnMainThread(^{
    [window toggleFullScreen:nil];
  });
}

void minimizeWindow(NSWindow *window) {
  runOnMainThread(^{
    [window miniaturize:nil];
  });
}

void closeWindow(NSWindow *window) {
  dispatch_async(dispatch_get_main_queue(), ^{
    [window close];
  });
}

void setWindowTitle(NSWindow *window, const char *title) {
  NSString *_title = [NSString stringWithUTF8String:title];
  runOnMainThread(^{
    [window setTitle:_title];
  });
}

double getTitleBarHeight(NSWindow *window) {
  BitsdojoWindowController *controller = getControllerForWindow(window);
  if (controller == nil)
    return 0;
  return controller.titleBarHeight;
}

BDWStatus getTitleBarButtonSize(NSWindow *window, BDWOffset *size) {
  if (window == nil || size == nil) {
    return BDW_FAILED;
  }
  NSButton *button = [window standardWindowButton:NSWindowCloseButton];
  if (button == nil) {
    return BDW_FAILED;
  }
  size->x = button.frame.size.width;
  size->y = button.frame.size.height;
  return BDW_SUCCESS;
}

double getWindowScaleFactor(NSWindow *window) {
  if (window == nil) {
    return 1.0;
  }
  NSScreen *screen = window.screen ?: [NSScreen mainScreen];
  if (screen == nil) {
    return 1.0;
  }
  return screen.backingScaleFactor;
}

void setAlwaysOnTop(NSWindow *window, int value) {
  runOnMainThread(^{
    [window setLevel:value == 1 ? NSFloatingWindowLevel : NSNormalWindowLevel];
  });
}

bool isAlwaysOnTop(NSWindow *window) {
  return window.level == NSFloatingWindowLevel;
}

void setBackgroundEffect(NSWindow *window, int effect) {
  runOnMainThread(^{
    BitsdojoWindowController *controller = getControllerForWindow(window);
    if (controller) {
      [controller applyBackgroundEffect:effect];
    }
  });
}

void setTitleBarHeight(NSWindow *window, int height) {
  BitsdojoWindowController *controller = getControllerForWindow(window);
  if (controller != nil) {
    controller.titleBarHeight = height;
  }
  [TitleBarButtonManager setCustomizeTitleBarHeight:height];
  // Re-adjust buttons for the current window
  runOnMainThread(^{
    [TitleBarButtonManager
        adjustButtonPositionsForWindow:[window styleMask] &
                                       NSWindowStyleMaskFullScreen
                             forWindow:window
                        withController:nil];
  });
}

bool isPrimaryWindow(NSWindow *window) {
  if (window == nil) {
    return false;
  }
  return window == _primaryWindow;
}

void terminateApp() {
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSApp terminate:nil];
  });
}

void setWindowButtonVisibility(NSWindow *window, int button, bool visible) {
  runOnMainThread(^{
    [TitleBarButtonManager setWindowButtonVisibility:window
                                              button:button
                                             visible:visible];
  });
}

void setWindowButtonOffset(NSWindow *window, int button, double x, double y) {
  runOnMainThread(^{
    [TitleBarButtonManager setWindowButtonOffset:window button:button x:x y:y];
  });
}

BDW_EXPORT void setHasShadow(NSWindow *window, int value) {
  runOnMainThread(^{
    [window setHasShadow:value == 1];
  });
}

BDW_EXPORT bool isHasShadow(NSWindow *window) {
  return window.hasShadow;
}
