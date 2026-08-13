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
  // Self-heal: a window whose controller registration was lost or never
  // happened (startup races in secondary engines) would otherwise take
  // setWindowCanBeShown as a silent no-op — and the makeKeyAndOrderFront
  // below would re-zero the alpha we just restored, permanently, via the
  // hide-on-startup branch in BitsdojoWindow.order().
  if (getControllerForWindow(window) == nil) {
    NSLog(@"[bitsdojo] showWindow: no controller for %@ — self-healing",
          window.title ?: @"<untitled>");
    setAppWindow(window);
  }
  setWindowCanBeShown(window, true);
  // Latch "this window has been explicitly shown" on the window itself
  // (KVC: the Swift class isn't visible from here). The order() override
  // consults it so no later orderFront can ever re-hide a shown window,
  // even if the controller lookup above failed too.
  @try {
    [window setValue:@YES forKey:@"hasEverBeenShown"];
  } @catch (NSException *exception) {
    // Not a BitsdojoWindow subclass: no hide-on-startup to latch away.
  }
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
  BitsdojoWindowController *controller = getControllerForWindow(window);
  NSRect frame = (controller != nil) ? controller.windowFrame : [window frame];
  // Keep the TOP-left fixed in the Dart (y-down) space: AppKit's origin is
  // the bottom-left, so a height change must shift origin.y by the delta or
  // the window's top edge moves (and drifts apart from the animated resize
  // path, which anchors the top-left via setRectForWindow).
  frame.origin.y += frame.size.height - height;
  frame.size.width = width;
  frame.size.height = height;
  if (controller != nil) {
    // Cache synchronously like setRect/setPosition, so reads before the
    // main-queue apply see the new size and a stale live-frame read can't
    // clobber a just-set origin.
    controller.windowFrame = frame;
  }
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


// Dart-side window coordinates are GLOBAL desktop coordinates: top-left of
// the PRIMARY screen is (0,0), y grows downward, other screens extend the
// plane (negative/overflow values are legal). Per-current-screen coordinates
// made every save/restore and every cross-screen animation reinterpret its
// numbers against whichever screen the window happened to be on -- measured
// on a dual-display rig as windows sized for one screen landing on the
// other and mid-animation reference switches ("flying").
static CGFloat bdwPrimaryScreenTopY(void) {
  NSScreen *primary = [NSScreen screens].firstObject; // origin (0,0) screen
  return primary.frame.origin.y + primary.frame.size.height;
}

BDWStatus getScreenInfoForWindow(NSWindow *window, BDWScreenInfo *screenInfo) {
  BitsdojoWindowController *controller = getControllerForWindow(window);
  if (controller == nil) {
    return BDW_FAILED;
  }
  auto workingScreenRect = controller.workingScreenRect;
  auto fullScreenRect = controller.fullScreenRect;
  CGFloat topY = bdwPrimaryScreenTopY();
  BDWRect *workingRect = screenInfo->workingRect;
  BDWRect *fullRect = screenInfo->fullRect;
  // Global space: alignment math done on these rects feeds straight into
  // setRect/setPosition without any per-screen re-basing.
  workingRect->left = workingScreenRect.origin.x;
  workingRect->top =
      topY - (workingScreenRect.origin.y + workingScreenRect.size.height);
  workingRect->right = workingRect->left + workingScreenRect.size.width;
  workingRect->bottom = workingRect->top + workingScreenRect.size.height;
  fullRect->left = fullScreenRect.origin.x;
  fullRect->top = topY - (fullScreenRect.origin.y + fullScreenRect.size.height);
  fullRect->right = fullRect->left + fullScreenRect.size.width;
  fullRect->bottom = fullRect->top + fullScreenRect.size.height;
  return BDW_SUCCESS;
}

BDWStatus setPositionForWindow(NSWindow *window, BDWOffset *offset) {
  // Copy the fields SYNCHRONOUSLY: the caller (Dart FFI) frees the struct
  // when this function returns, and the blocks below run later on the main
  // queue -- reading offset-> inside them is use-after-free (surfaced as a
  // NaN frame crashing setFrameTopLeftPoint).
  CGFloat offsetX = offset->x;
  CGFloat offsetY = offset->y;
  NSPoint position;
  position.x = offsetX;
  position.y = bdwPrimaryScreenTopY() - offsetY;
  // Update the cached frame synchronously ON THE CALLING THREAD (matching
  // setRectForWindow): getRectForWindow reads the cache, and a read between
  // this call and the main-queue apply must see the new position. Wrapping
  // this in runOnMainThread deferred the cache write too whenever the FFI
  // call arrived off the main thread.
  BitsdojoWindowController *controller = getControllerForWindow(window);
  if (controller != nil) {
    NSRect f = controller.windowFrame;
    f.origin.x = position.x;
    f.origin.y = position.y - f.size.height;
    controller.windowFrame = f;
  }
  // Single dispatch hop, like setRect/setSize: the previous
  // runOnMainThread + nested dispatch_async double-queued the apply, so a
  // later single-hop resize could run FIRST and clobber this move.
  dispatch_async(dispatch_get_main_queue(), ^{
    [window setFrameTopLeftPoint:position];
  });
  return BDW_SUCCESS;
}

BDWStatus setRectForWindow(NSWindow *window, BDWRect *rect) {
  BitsdojoWindowController *controller = getControllerForWindow(window);

  if (controller == nil) {
    return BDW_FAILED;
  }
  NSRect frame;
  frame.size.width = rect->right - rect->left;
  frame.size.height = rect->bottom - rect->top;
  frame.origin.x = rect->left;
  frame.origin.y = bdwPrimaryScreenTopY() - rect->bottom;
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
  NSRect frame = controller.windowFrame;
  rect->left = frame.origin.x;
  auto frameTop = frame.origin.y + frame.size.height;
  rect->top = bdwPrimaryScreenTopY() - frameTop;
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
