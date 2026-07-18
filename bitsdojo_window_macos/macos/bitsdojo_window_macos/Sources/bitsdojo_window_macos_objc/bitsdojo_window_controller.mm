#import "bitsdojo_window_controller.h"
#import "titlebar_button_manager.h"
#import <QuartzCore/QuartzCore.h>
#include <cstdio>

// Helper function to keep visual effect view at the bottom
NSComparisonResult ensureVisualEffectAtBottom(__kindof NSView *_Nonnull view1,
                                              __kindof NSView *_Nonnull view2,
                                              void *_Nullable context) {
  NSVisualEffectView *effectView = (__bridge NSVisualEffectView *)context;
  if (view1 == effectView)
    return NSOrderedAscending;
  if (view2 == effectView)
    return NSOrderedDescending;
  return NSOrderedSame;
}

@implementation BitsdojoWindowController

- (instancetype)initWithWindow:(NSWindow *)window {
  self = [super init];
  if (self && window) {
    self.window = window;
    self.window.delegate = self;

    // Explicitly subscribe to fullscreen notifications to ensure we capture
    // them even if the window delegate is overwritten by another plugin.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowDidEnterFullScreen:)
               name:NSWindowDidEnterFullScreenNotification
             object:self.window];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowWillExitFullScreen:)
               name:NSWindowWillExitFullScreenNotification
             object:self.window];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowWillEnterFullScreen:)
               name:NSWindowWillEnterFullScreenNotification
             object:self.window];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowDidExitFullScreen:)
               name:NSWindowDidExitFullScreenNotification
             object:self.window];

    self.titleBarHeight = 28.0; // Default standard height

    SEL titleBarHeightSelector =
        NSSelectorFromString(@"bitsdojo_window_title_bar_height");

    if ([self.window respondsToSelector:titleBarHeightSelector]) {
      // Use dynamic dispatch to call the Swift method
      CGFloat height = ((CGFloat (*)(
          id, SEL))[self.window methodForSelector:titleBarHeightSelector])(
          self.window, titleBarHeightSelector);
      self.titleBarHeight = height;
    }

    self.canBeShown = NO;
    [TitleBarButtonManager adjustButtonPositionsForWindow:false
                                                forWindow:self.window
                                           withController:self];
    [self onScreenChange];

    // Note: previously this controller installed KVO observers on
    // `opaque` and `backgroundColor`. The callback did nothing
    // (all NSLog lines were commented out) AND the dealloc-time
    // teardown walked `contentView.subviews` removing KVOs that
    // were never added — those KVO calls were dead code, removed
    // along with `observeValueForKeyPath` and the cleanup blocks
    // in `dealloc` / `windowWillClose`.
  }
  return self;
}

- (void)dealloc {
  // 🔧 Explicitly invalidate timer
  [self stopFullScreenTransitionMonitoring];

  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onScreenChange {
  self.isVisible = self.window.isVisible;
  self.isZoomed = self.window.isZoomed;
  [self setupScreenRects];
  [self setupWindowRects];
}

- (void)setupWindowRects {
  self.windowFrame = self.window.frame;
}

- (void)setupScreenRects {
  NSScreen *screen = self.window.screen;
  self.workingScreenRect = screen.visibleFrame;
  self.fullScreenRect = screen.frame;
}

- (void)windowDidResize:(NSNotification *)notification {
  NSWindow *resizedWindow = notification.object;
  if ([resizedWindow isKindOfClass:[NSWindow class]]) {
    [self setupWindowRects];
    self.windowSize = self.window.frame.size;
  }
}

- (void)handleWindowChanges {
  self.isZoomed = self.window.isZoomed;
}

- (void)windowDidBecomeVisible:(NSNotification *)notification {
  self.isVisible = YES;
}

- (void)windowDidBecomeHidden:(NSNotification *)notification {
  self.isVisible = NO;
}

- (void)windowDidChangeScreen:(NSNotification *)notification {
  [self onScreenChange];
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
  [self onScreenChange];
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
  [self handleWindowChanges];
}
- (void)windowDidDeminiaturize:(NSNotification *)notification {
  [self handleWindowChanges];
}
- (void)windowDidEndLiveResize:(NSNotification *)notification {
  [self handleWindowChanges];
}

/// Recursively force-transparent every CALayer in the subtree.
///
/// Why recursion is necessary: Flutter on Apple Silicon renders via
/// CAMetalLayer which defaults to `isOpaque = true` (a fill-rate
/// optimization). The CAMetalLayer lives as a sublayer of FlutterView
/// at an unspecified depth, sometimes created lazily AFTER
/// setupFlutter completes. Just clearing the top-level NSWindow or
/// contentView layer's opacity isn't enough — when macOS evicts the
/// window's backing store during a long Spaces occlusion and the user
/// swipes back, that opaque CAMetalLayer composites with its default
/// fill (≈ white) before Flutter produces a fresh frame. We walk the
/// whole layer tree so every layer is non-opaque + clear-bg.
static void bdwMakeLayerTreeTransparent(CALayer *layer) {
  if (layer == nil) return;
  if (layer.opaque) {
    layer.opaque = NO;
  }
  CGColorRef clear = [[NSColor clearColor] CGColor];
  if (layer.backgroundColor != NULL &&
      !CGColorEqualToColor(layer.backgroundColor, clear)) {
    layer.backgroundColor = clear;
  }
  for (CALayer *sub in layer.sublayers) {
    bdwMakeLayerTreeTransparent(sub);
  }
}

- (void)forceTransparency {
  [self.window setOpaque:NO];
  [self.window setBackgroundColor:[NSColor clearColor]];

  NSView *contentView = [self.window contentView];
  if (contentView) {
    [contentView setWantsLayer:YES];
    bdwMakeLayerTreeTransparent([contentView layer]);

    // FlutterView / FlutterSurfaceView sometimes sit at depth 1
    // (under contentView) with their own layer. The recursive walk
    // above already handles them, but we keep the explicit subview
    // loop as a belt-and-suspenders for view hierarchies where the
    // FlutterView is itself a content-view sibling rather than a
    // child of contentView's layer.
    for (NSView *subview in [contentView subviews]) {
      NSString *className = NSStringFromClass([subview class]);
      if ([className containsString:@"FlutterView"] ||
          [className containsString:@"FlutterSurface"]) {
        [subview setWantsLayer:YES];
        bdwMakeLayerTreeTransparent([subview layer]);
      }
    }
  }

  NSViewController *controller = [self.window contentViewController];
  if (controller && [controller view]) {
    NSView *view = [controller view];
    [view setWantsLayer:YES];
    bdwMakeLayerTreeTransparent([view layer]);
  }
}

- (void)stopFullScreenTransitionMonitoring {
  if (self.fullScreenTransitionTimer) {
    [self.fullScreenTransitionTimer invalidate];
    self.fullScreenTransitionTimer = nil;
  }
}

- (void)enforceTransparencyDuringTransition {
  if ([self.window isOpaque]) {
    [self.window setOpaque:NO];
  }
  if (![[self.window backgroundColor] isEqual:[NSColor clearColor]]) {
    [self.window setBackgroundColor:[NSColor clearColor]];
  }

  NSView *contentView = [self.window contentView];
  NSVisualEffectView *visualEffectView = nil;

  for (NSView *subview in [contentView subviews]) {
    if ([subview isKindOfClass:[NSVisualEffectView class]]) {
      visualEffectView = (NSVisualEffectView *)subview;
      break;
    }
  }

  if (visualEffectView && visualEffectView.superview) {
    NSArray *subviews = contentView.subviews;
    if (subviews.firstObject != visualEffectView) {
      [contentView sortSubviewsUsingFunction:ensureVisualEffectAtBottom
                                     context:(__bridge void *)visualEffectView];
    }
  }
}

- (void)applyBackgroundEffect:(int)effect {
  self.lastBackgroundEffect = effect;
  NSWindow *window = self.window;
  NSView *contentView = [window contentView];
  NSVisualEffectView *visualEffectView = nil;

  for (NSView *subview in [contentView subviews]) {
    if ([subview isKindOfClass:[NSVisualEffectView class]]) {
      visualEffectView = (NSVisualEffectView *)subview;
      break;
    }
  }

  // Tell BitsdojoWindow whether it should sticky-clamp its
  // backgroundColor to clear (any translucent mode) or behave like a
  // normal opaque NSWindow (Disabled mode). Without this the sticky
  // backgroundColor override couldn't tell the two apart and would
  // always force clear — breaking apps that explicitly opt out of
  // background effects.
  SEL setWantsTransparentSel =
      NSSelectorFromString(@"setWantsTransparentBackground:");
  if ([window respondsToSelector:setWantsTransparentSel]) {
    NSMethodSignature *sig = [window methodSignatureForSelector:setWantsTransparentSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:window];
    [inv setSelector:setWantsTransparentSel];
    BOOL wantsTransparent = (effect != 0);
    [inv setArgument:&wantsTransparent atIndex:2];
    [inv invoke];
  }

  if (effect == 0) { // Disabled
    if (![window isOpaque])
      [window setOpaque:YES];
    if (![[window backgroundColor] isEqual:[NSColor windowBackgroundColor]])
      [window setBackgroundColor:[NSColor windowBackgroundColor]];

    if (!([window styleMask] & NSWindowStyleMaskFullSizeContentView)) {
      if ([window titlebarAppearsTransparent])
        [window setTitlebarAppearsTransparent:NO];
    }
    if (visualEffectView) {
      [visualEffectView removeFromSuperview];
    }
  } else {
    [window setOpaque:NO];
    [window setBackgroundColor:[NSColor clearColor]];
    [window setTitlebarAppearsTransparent:YES];

    if (@available(macOS 11.0, *)) {
      [window setTitlebarSeparatorStyle:NSTitlebarSeparatorStyleNone];
    }

    [self forceTransparency];

    if (effect == 1) { // Transparent
      if (visualEffectView) {
        [visualEffectView removeFromSuperview];
      }
    } else { // Acrylic (2), Mica (3)
      if (!visualEffectView) {
        visualEffectView =
            [[NSVisualEffectView alloc] initWithFrame:[contentView bounds]];
        [visualEffectView
            setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [visualEffectView
            setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
        [visualEffectView setState:NSVisualEffectStateActive];

        [visualEffectView setWantsLayer:YES];
        [contentView addSubview:visualEffectView
                     positioned:NSWindowBelow
                     relativeTo:nil];

        [contentView
            sortSubviewsUsingFunction:ensureVisualEffectAtBottom
                              context:(__bridge void *)visualEffectView];
      }

      NSVisualEffectMaterial targetMaterial;
      BOOL isFullScreen =
          ([window styleMask] & NSWindowStyleMaskFullScreen) != 0;

      if (effect == 2) { // Acrylic
        if (isFullScreen) {
          targetMaterial = NSVisualEffectMaterialHeaderView;
        } else {
          targetMaterial = NSVisualEffectMaterialFullScreenUI;
        }
      } else { // Mica (3)
        targetMaterial = NSVisualEffectMaterialUnderWindowBackground;
      }

      [visualEffectView setMaterial:targetMaterial];
      [visualEffectView setState:NSVisualEffectStateActive];
      [visualEffectView setBlendingMode:NSVisualEffectBlendingModeBehindWindow];

      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      [visualEffectView setNeedsDisplay:YES];
      [CATransaction commit];
    }
  }
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification {

  NSButton *closeButton =
      [self.window standardWindowButton:NSWindowCloseButton];
  NSButton *minButton =
      [self.window standardWindowButton:NSWindowMiniaturizeButton];
  NSButton *zoomButton = [self.window standardWindowButton:NSWindowZoomButton];

  self.wasCloseButtonVisible = !closeButton.isHidden;
  self.wasMiniaturizeButtonVisible = !minButton.isHidden;
  self.wasZoomButtonVisible = !zoomButton.isHidden;

  [self.window setHasShadow:NO];

  [self forceTransparency];

  NSView *contentView = [self.window contentView];
  NSVisualEffectView *visualEffectView = nil;

  for (NSView *subview in [contentView subviews]) {
    if ([subview isKindOfClass:[NSVisualEffectView class]]) {
      visualEffectView = (NSVisualEffectView *)subview;
      break;
    }
  }

  if (visualEffectView) {
    [contentView sortSubviewsUsingFunction:ensureVisualEffectAtBottom
                                   context:(__bridge void *)visualEffectView];
  }

  [self startFullScreenTransitionMonitoring];
}

- (void)startFullScreenTransitionMonitoring {
  if (self.fullScreenTransitionTimer) {
    [self.fullScreenTransitionTimer invalidate];
  }

  // During the macOS fullscreen transition animation (~0.5-0.7 s)
  // the OS occasionally resets window opacity / background color
  // back to system defaults — which would expose a non-transparent
  // flash mid-transition for windows configured with a background
  // effect. We poll-enforce transparency at 10 fps for the duration
  // of the transition and stop in windowDid{Enter,Exit}FullScreen.
  //
  // The per-tick cost is small (one or two cheap NSWindow property
  // reads + maybe one set + a contentView.subviews scan), so the
  // CPU drain is bounded by the short transition window.
  self.fullScreenTransitionTimer =
      [NSTimer scheduledTimerWithTimeInterval:0.1 // 10fps
                                       target:self
                                     selector:@selector
                                     (enforceTransparencyDuringTransition)
                                     userInfo:nil
                                      repeats:YES];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
  [self stopFullScreenTransitionMonitoring];

  // Apply transparency + background effect ONCE at the end of the
  // transition. The historical "dispatch_after 0.1s, do it again"
  // double-apply was a defensive workaround for an older flicker
  // that no longer reproduces on modern macOS — and it caused a
  // visible second redraw 100 ms after the transition completed.
  [self forceTransparency];
  [self applyBackgroundEffect:self.lastBackgroundEffect];

  [TitleBarButtonManager showTitleBarButtonsForWindow:self.window];
  [TitleBarButtonManager adjustButtonPositionsForWindow:true
                                              forWindow:self.window
                                         withController:self];
}

- (void)windowWillExitFullScreen:(NSNotification *)notification {
  [self.window setHasShadow:NO];
  [self forceTransparency];

  NSView *contentView = [self.window contentView];
  NSVisualEffectView *visualEffectView = nil;

  for (NSView *subview in [contentView subviews]) {
    if ([subview isKindOfClass:[NSVisualEffectView class]]) {
      visualEffectView = (NSVisualEffectView *)subview;
      break;
    }
  }

  if (visualEffectView) {
    [contentView sortSubviewsUsingFunction:ensureVisualEffectAtBottom
                                   context:(__bridge void *)visualEffectView];
  }

  [self startFullScreenTransitionMonitoring];

  NSButton *closeButton =
      [self.window standardWindowButton:NSWindowCloseButton];
  NSButton *minButton =
      [self.window standardWindowButton:NSWindowMiniaturizeButton];
  NSButton *zoomButton = [self.window standardWindowButton:NSWindowZoomButton];

  closeButton.hidden = !self.wasCloseButtonVisible;
  minButton.hidden = !self.wasMiniaturizeButtonVisible;
  zoomButton.hidden = !self.wasZoomButtonVisible;

  [TitleBarButtonManager adjustButtonPositionsForWindow:false
                                              forWindow:self.window
                                         withController:self];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
  [self stopFullScreenTransitionMonitoring];

  // Same simplification as windowDidEnterFullScreen — drop the
  // delayed double-apply that caused a second redraw 100 ms after
  // the transition.
  [self forceTransparency];
  [self applyBackgroundEffect:self.lastBackgroundEffect];

  [self.window setHasShadow:YES];
}

- (void)windowDidChangeOcclusionState:(NSNotification *)notification {
  BOOL nowVisible =
      (self.window.occlusionState & NSWindowOcclusionStateVisible) != 0;
  BOOL wasVisible = self.isVisible;
  self.isVisible = nowVisible;

  // Only re-apply on a REAL occluded -> visible transition. macOS delivers
  // this notification whenever it recomputes occlusion, which — during PiP,
  // where the host animates the window at ~60fps AND toggles alwaysOnTop
  // (window level/stacking) — happens in bursts, often reporting "still
  // visible". Without the wasVisible gate we re-ran forceTransparency +
  // applyBackgroundEffect + setNeedsDisplay on every such spurious tick, a
  // native redraw churn that reads as the window "constantly refreshing".
  // A genuine occluded->visible flip always has wasVisible == NO, so the
  // white-flash guard below still fires exactly when it's needed.
  if (!nowVisible || wasVisible) {
    return;
  }

  // Re-apply transparency + background effect when the window becomes
  // visible again after occlusion.
  //
  // Why: macOS occasionally resets a window's `opaque` / `backgroundColor`
  // properties (and detaches NSVisualEffectView state) when it's been
  // off-screen — most visibly when the user swipes across Spaces to a window
  // configured with a translucent background effect. Without re-applying, the
  // first frame after the swipe shows the OS default opaque white window bg,
  // producing a visible "white flash" before Flutter repaints.
  //
  // This is CHEAP (idempotent property writes; the heavy work is gated by
  // isOpaque / backgroundColor equality checks inside forceTransparency). It
  // does NOT call `[self.window display]` or `invalidateShadow` like the
  // original "Aggressive Wake Up Strategy" did — those were the source of the
  // mid-space-swipe synchronous redraw flicker we already removed.
  [self forceTransparency];
  if (self.lastBackgroundEffect > 0) {
    [self applyBackgroundEffect:self.lastBackgroundEffect];
  }

  // Mark Flutter content view dirty so the display link picks up a fresh
  // frame on the next vsync.
  [self.window.contentView setNeedsDisplay:YES];
}

- (void)windowWillClose:(NSNotification *)notification {
  // 0. Stop the fullscreen-transition poll timer. It retains `self` (target),
  // so if the window is closed mid-fullscreen-transition — before
  // windowDid{Enter,Exit}FullScreen stops it — it runs forever at 10fps on a
  // nil-window controller and blocks dealloc (a leaked timer + CPU drain per
  // such close).
  [self stopFullScreenTransitionMonitoring];

  // 1. Remove NSNotificationCenter observers
  [[NSNotificationCenter defaultCenter]
      removeObserver:self
                name:NSWindowDidEnterFullScreenNotification
              object:self.window];
  [[NSNotificationCenter defaultCenter]
      removeObserver:self
                name:NSWindowWillExitFullScreenNotification
              object:self.window];
  [[NSNotificationCenter defaultCenter]
      removeObserver:self
                name:NSWindowWillEnterFullScreenNotification
              object:self.window];
  [[NSNotificationCenter defaultCenter]
      removeObserver:self
                name:NSWindowDidExitFullScreenNotification
              object:self.window];

  // 2. Detach FlutterViewController to prevent invalid engine handle errors
  // If the engine is already dead, separating the controller helps it die
  // peacefully
  if ([self.window.contentViewController
          isKindOfClass:NSClassFromString(@"FlutterViewController")]) {
    self.window.contentViewController = nil;
  }

  self.window.delegate = nil;
  self.window = nil;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
  // We notify the Dart side that a close was requested.
  // The Dart side will then decide whether to actually close the window or not.

  // Using dynamic dispatch to call the Swift method to avoid header import
  // issues.
  Class pluginClass =
      NSClassFromString(@"bitsdojo_window_macos.BitsdojoWindowPlugin");
  // If the above doesn't work (due to namespace), try without project name
  if (!pluginClass) {
    pluginClass = NSClassFromString(@"BitsdojoWindowPlugin");
  }

  SEL closeRequestedSelector = NSSelectorFromString(@"closeRequested:");
  if (pluginClass && [pluginClass respondsToSelector:closeRequestedSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [pluginClass performSelector:closeRequestedSelector withObject:sender];
#pragma clang diagnostic pop
  } else {
    // If we can't find the plugin class or method, just close the window
    return YES;
  }

  return NO; // Return NO to prevent the window from closing immediately.
}

@end
