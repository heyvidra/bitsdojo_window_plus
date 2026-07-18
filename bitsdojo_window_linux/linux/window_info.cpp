#include <glib.h>
#include "./window_info.h"

namespace bitsdojo_window {

GHashTable* windows_table = nullptr;

static void destroyWindowInfo(gpointer data) {
    delete reinterpret_cast<WindowInfo*>(data);
}

WindowInfo* getWindowInfo(GtkWindow* window) {
    if (nullptr == windows_table) {
        windows_table = g_hash_table_new_full(
            g_direct_hash, g_direct_equal, nullptr, destroyWindowInfo);
    }
    WindowInfo* windowInfo;
    windowInfo = reinterpret_cast<WindowInfo*>(
        g_hash_table_lookup(windows_table, window));
    if (nullptr != windowInfo) {
        return windowInfo;
    }

    windowInfo = new WindowInfo();
    windowInfo->x = 0;
    windowInfo->y = 0;
    windowInfo->width = 0;
    windowInfo->height = 0;
    windowInfo->screenX = 0;
    windowInfo->screenY = 0;
    windowInfo->screenWidth = 0;
    windowInfo->screenHeight = 0;
    windowInfo->minWidth = -1;
    windowInfo->minHeight = -1;
    windowInfo->maxWidth = -1;
    windowInfo->maxHeight = -1;
    windowInfo->scaleFactor = 1;
    windowInfo->gripSize = 6;
    g_hash_table_insert(windows_table, window, windowInfo);
    return windowInfo;
}

void removeWindowInfo(GtkWindow* window) {
    if (nullptr == windows_table || window == nullptr) {
        return;
    }
    g_hash_table_remove(windows_table, window);
}

}  // namespace bitsdojo_window
