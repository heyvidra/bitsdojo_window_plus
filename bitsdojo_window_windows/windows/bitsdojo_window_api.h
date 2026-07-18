#ifndef BITSDOJO_WINDOW_API_H
#define BITSDOJO_WINDOW_API_H

#include "./bitsdojo_window.h"
#include "./bitsdojo_window_common.h"

namespace bitsdojo_window {

typedef struct _BDWPrivateAPI {
  TDragAppWindow dragAppWindow;
} BDWPrivateAPI;

typedef struct _BDWPublicAPI {
  TIsBitsdojoWindowLoaded isBitsdojoWindowLoaded;
  TGetAppWindow getAppWindow;
  TSetWindowCanBeShown setWindowCanBeShown;
  TSetMinSize setMinSize;
  TSetMaxSize setMaxSize;
  TSetWindowCutOnMaximize setWindowCutOnMaximize;
  TIsDPIAware isDPIAware;
  TIsAlwaysOnTop isAlwaysOnTop;
  TSetAlwaysOnTop setAlwaysOnTop;
  TSetCloseRequestedCallback setCloseRequestedCallback;
  TSetBackgroundEffect setBackgroundEffect;
} BDWPublicAPI;

} // namespace bitsdojo_window

typedef struct _BDWAPI {
  bitsdojo_window::BDWPublicAPI *publicAPI;
  bitsdojo_window::BDWPrivateAPI *privateAPI;
} BDWAPI;

BDW_EXPORT BDWAPI *bitsdojo_window_api();
#endif