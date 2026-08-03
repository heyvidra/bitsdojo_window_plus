#ifndef MULTI_WINDOW_MANAGER_H_
#define MULTI_WINDOW_MANAGER_H_

#include <gtk/gtk.h>
#include <string>

class MultiWindowManager {
public:
  static MultiWindowManager &GetInstance();

  void SetDartEntrypointArguments(char **args);

  // has_position distinguishes "caller supplied x/y" from the 0,0 default —
  // without it, unpositioned child windows are forced to the screen origin.
  void OpenNewWindow(const char *name, const char *arguments, double width,
                     double height, double x, double y,
                     bool has_position = false);

private:
  MultiWindowManager();
  ~MultiWindowManager();

  MultiWindowManager(const MultiWindowManager &) = delete;
  MultiWindowManager &operator=(const MultiWindowManager &) = delete;

  char **dart_entrypoint_arguments_ = nullptr;
};

#endif // MULTI_WINDOW_MANAGER_H_
