#import "titlebar_button_manager.h"
#import "bitsdojo_window_controller.h"
#include <cstdio>

// Forward declaration of the search function from bitsdojo_window.mm
#ifdef __cplusplus
extern "C" {
#endif
BitsdojoWindowController *getControllerForWindow(NSWindow *window);
#ifdef __cplusplus
}
#endif

@implementation TitleBarButtonManager

int _normalTitleBarHeight = 28;

+ (void)showTitleBarButtonsForWindow:(NSWindow *)window {
  [self setButtonVisibility:YES forWindow:window];
}

+ (void)hideTitleBarButtonsForWindow:(NSWindow *)window {
  [self setButtonVisibility:NO forWindow:window];
}

+ (void)setButtonVisibility:(BOOL)visible forWindow:(NSWindow *)window {
  NSArray *buttons = @[
    [window standardWindowButton:NSWindowCloseButton],
    [window standardWindowButton:NSWindowMiniaturizeButton],
    [window standardWindowButton:NSWindowZoomButton]
  ];
  for (NSButton *button in buttons) {
    button.hidden = !visible;
  }
}

+ (void)adjustButtonPositionsForWindow:(BOOL)fullscreen
                             forWindow:(NSWindow *)window
                        withController:(BitsdojoWindowController *)controller {

  NSButton *closeButton = [window standardWindowButton:NSWindowCloseButton];
  NSButton *minButton = [window standardWindowButton:NSWindowMiniaturizeButton];
  NSButton *zoomButton = [window standardWindowButton:NSWindowZoomButton];

  NSMutableArray *buttons = [NSMutableArray array];
  if (closeButton && ![closeButton isHidden])
    [buttons addObject:closeButton];
  if (minButton && ![minButton isHidden])
    [buttons addObject:minButton];
  if (zoomButton && ![zoomButton isHidden])
    [buttons addObject:zoomButton];

  NSUInteger count = [buttons count];

  CGFloat currentHeight = 28.0; // Default standard height

  if (!fullscreen) {
    if (!controller) {
      controller = getControllerForWindow(window);
    }
    if (controller) {
      currentHeight = controller.titleBarHeight;
    }
  }
  // Calculate start X based on height: 30pt -> 12pt, 50pt -> 21pt
  CGFloat startX = 8.0;
  if (currentHeight > 28) {
    CGFloat factor =
        (MAX(currentHeight, _normalTitleBarHeight) - _normalTitleBarHeight) /
        20.0;
    startX = 8.0 + (21.0 - 8.0) * factor;
  }

  for (NSUInteger i = 0; i < count; i++) {
    NSButton *button = buttons[i];
    CGFloat newY = (currentHeight - button.frame.size.height) / 2;
    CGFloat newX = startX + i * 20;

    // Hidden buttons are filtered out above

    [self adjustButtonPosition:button withOffsetX:newX withOffsetY:newY];
  }
}

+ (void)setWindowButtonVisibility:(NSWindow *)window
                           button:(int)buttonIndex
                          visible:(BOOL)visible {
  NSButton *button = [window standardWindowButton:(NSWindowButton)buttonIndex];
  if (button) {
    button.hidden = !visible;
    // Trigger re-layout after visibility change
    [self adjustButtonPositionsForWindow:([window styleMask] &
                                          NSWindowStyleMaskFullScreen)
                               forWindow:window
                          withController:nil];
  }
}

+ (void)setWindowButtonOffset:(NSWindow *)window
                       button:(int)buttonIndex
                            x:(double)x
                            y:(double)y {
  NSButton *button = [window standardWindowButton:(NSWindowButton)buttonIndex];
  if (button) {
    [self adjustButtonPosition:button withOffsetX:x withOffsetY:y];
  }
}

+ (void)adjustButtonPosition:(NSButton *)button
                 withOffsetX:(CGFloat)xOffset
                 withOffsetY:(CGFloat)yOffset {
  button.translatesAutoresizingMaskIntoConstraints = NO;
  NSView *superview = button.superview;
  if (!superview)
    return;

  // Faster constraint removal by only checking if the constraint involves the
  // button
  for (NSLayoutConstraint *constraint in superview.constraints) {
    if (constraint.firstItem == button || constraint.secondItem == button) {
      [superview removeConstraint:constraint];
    }
  }

  NSLayoutConstraint *topConstraint =
      [NSLayoutConstraint constraintWithItem:button
                                   attribute:NSLayoutAttributeTop
                                   relatedBy:NSLayoutRelationEqual
                                      toItem:superview
                                   attribute:NSLayoutAttributeTop
                                  multiplier:1.0
                                    constant:yOffset];

  NSLayoutConstraint *leftConstraint =
      [NSLayoutConstraint constraintWithItem:button
                                   attribute:NSLayoutAttributeLeft
                                   relatedBy:NSLayoutRelationEqual
                                      toItem:superview
                                   attribute:NSLayoutAttributeLeft
                                  multiplier:1.0
                                    constant:xOffset];

  [superview addConstraints:@[ topConstraint, leftConstraint ]];
}

+ (void)setCustomizeTitleBarHeight:(int)height {
  // Deprecated, we use per-window height now
}

@end
