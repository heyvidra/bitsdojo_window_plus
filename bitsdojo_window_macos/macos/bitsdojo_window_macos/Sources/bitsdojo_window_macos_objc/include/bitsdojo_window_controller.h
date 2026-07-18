#import <Cocoa/Cocoa.h>

@interface BitsdojoWindowController : NSObject <NSWindowDelegate>

@property(assign) CGSize windowSize;
@property(assign) bool isVisible;
@property(assign) bool isZoomed;
@property(assign) bool canBeShown;
@property(assign) double titleBarHeight;

@property(nonatomic, assign) NSWindow *window;
@property(assign) NSRect workingScreenRect;
@property(assign) NSRect fullScreenRect;
@property(assign) NSRect windowFrame;
@property(assign) BOOL wasCloseButtonVisible;
@property(assign) BOOL wasMiniaturizeButtonVisible;
@property(assign) BOOL wasZoomButtonVisible;

@property(assign) int lastBackgroundEffect;

- (instancetype)initWithWindow:(NSWindow *)window;
- (void)applyBackgroundEffect:(int)effect;

@property(nonatomic, strong) NSTimer *fullScreenTransitionTimer;
- (void)startFullScreenTransitionMonitoring;
- (void)stopFullScreenTransitionMonitoring;
- (void)enforceTransparencyDuringTransition;

@end
