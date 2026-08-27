#ifndef MULTI_WINDOW_MANAGER_H_
#define MULTI_WINDOW_MANAGER_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <map>
#include <string>

class MultiWindowManager {
public:
  static MultiWindowManager &GetInstance();

  void SetDartEntrypointArguments(char **args);

  // has_position distinguishes "caller supplied x/y" from the 0,0 default —
  // without it, unpositioned child windows are forced to the screen origin.
  // modality is the wire string ("modeless"/"modal"; null or unknown means
  // none) and parent is the calling engine's own window — only consulted when
  // modality is set. notify_channel is the spawning plugin's method channel:
  // the child-exit watch reports 'windowClosed' (and any dialog result) back
  // into the engine that asked for the window.
  void OpenNewWindow(const char *name, const char *arguments, double width,
                     double height, double x, double y,
                     bool has_position = false, const char *modality = nullptr,
                     GtkWindow *parent = nullptr,
                     FlMethodChannel *notify_channel = nullptr);

  // Called from the modal child-exit watch. Re-enables the parent only once
  // its last outstanding modal child has exited. Deliberately does NOT
  // re-focus it — focus return is the WM's job (see the comment in the
  // implementation for why presenting here would misbehave on named reuse).
  void ReleaseModalParent(GtkWindow *parent);

private:
  MultiWindowManager();
  ~MultiWindowManager();

  MultiWindowManager(const MultiWindowManager &) = delete;
  MultiWindowManager &operator=(const MultiWindowManager &) = delete;

  char **dart_entrypoint_arguments_ = nullptr;

  // Outstanding modal dialog processes per parent window; the parent stays
  // insensitive until its count drops to zero, so several modal children of
  // one parent cannot re-enable it early.
  std::map<GtkWindow *, int> modal_counts_;
};

#endif // MULTI_WINDOW_MANAGER_H_
