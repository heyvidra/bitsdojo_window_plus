#import <Cocoa/Cocoa.h>

@class BitsdojoWindowController;
@interface TitleBarButtonManager : NSObject

+ (void)adjustButtonPositionsForWindow:(BOOL)fullscreen
                             forWindow:(NSWindow *)window
                        withController:(BitsdojoWindowController *)controller;
+ (void)showTitleBarButtonsForWindow:(NSWindow *)window;
+ (void)hideTitleBarButtonsForWindow:(NSWindow *)window;
+ (void)setCustomizeTitleBarHeight:(int)height;

+ (void)setWindowButtonVisibility:(NSWindow *)window
                           button:(int)button
                          visible:(BOOL)visible;

+ (void)setWindowButtonOffset:(NSWindow *)window
                       button:(int)button
                            x:(double)x
                            y:(double)y;

@end