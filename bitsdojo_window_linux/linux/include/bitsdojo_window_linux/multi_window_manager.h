#ifndef MULTI_WINDOW_MANAGER_H_
#define MULTI_WINDOW_MANAGER_H_

#include <gtk/gtk.h>
#include <string>

class MultiWindowManager {
public:
  static MultiWindowManager &GetInstance();

  void SetDartEntrypointArguments(char **args);

  void OpenNewWindow(const char *name, const char *arguments, double width,
                     double height, double x, double y);

private:
  MultiWindowManager();
  ~MultiWindowManager();

  MultiWindowManager(const MultiWindowManager &) = delete;
  MultiWindowManager &operator=(const MultiWindowManager &) = delete;

  char **dart_entrypoint_arguments_ = nullptr;
};

#endif // MULTI_WINDOW_MANAGER_H_
