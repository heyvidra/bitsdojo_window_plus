#import "bitsdojo_window_api.h"
#import "bitsdojo_window.h"

BDWPrivateAPI privateAPI = {
    .windowCanBeShown = windowCanBeShown,
    .setAppWindow = setAppWindow,
    .appWindowIsSet = appWindowIsSet,
};

BDWPublicAPI publicAPI = {
    .getAppWindow = getAppWindow,
    .setWindowCanBeShown = setWindowCanBeShown,
    .setInsideDoWhenWindowReady = setInsideDoWhenWindowReady,
    .showWindow = showWindow,
    .hideWindow = hideWindow,
    .moveWindow = moveWindow,
    .setSize = setSize,
    .setMinSize = setMinSize,
    .setMaxSize = setMaxSize,
    .getScreenInfoForWindow = getScreenInfoForWindow,
    .setPositionForWindow = setPositionForWindow,
    .setRectForWindow = setRectForWindow,
    .getRectForWindow = getRectForWindow,
    .isWindowVisible = isWindowVisible,
    .isWindowMaximized = isWindowMaximized,
    .maximizeOrRestoreWindow = maximizeOrRestoreWindow,
    .maximizeWindow = maximizeWindow,
    .toggleFullScreen = toggleFullScreen,
    .minimizeWindow = minimizeWindow,
    .closeWindow = closeWindow,
    .setWindowTitle = setWindowTitle,
    .getTitleBarHeight = getTitleBarHeight,
    .getTitleBarButtonSize = getTitleBarButtonSize,
    .getWindowScaleFactor = getWindowScaleFactor,
    .setAlwaysOnTop = setAlwaysOnTop,
    .isAlwaysOnTop = isAlwaysOnTop,
    .setBackgroundEffect = (TSetBackgroundEffect)setBackgroundEffect,
    .setTitleBarHeight = (TSetTitleBarHeight)setTitleBarHeight,
    .isPrimaryWindow = isPrimaryWindow,
    .terminateApp = terminateApp,
    .setWindowButtonVisibility = setWindowButtonVisibility,
    .setWindowButtonOffset = setWindowButtonOffset,
};

BDWAPI bdwAPI = {
    .publicAPI = &publicAPI,
    .privateAPI = &privateAPI,
};

BDW_EXPORT BDWAPI *bitsdojo_window_api() { return &bdwAPI; }
