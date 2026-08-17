cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "bitsdojo_window_windows")
set(PARENT_PROJECT_NAME,"bitsdojo_window")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

add_library(${PLUGIN_NAME} STATIC
  "bitsdojo_window.cpp"
  "bitsdojo_window_api.cpp"
  "bitsdojo_window_plugin.cpp"
  "multi_window_manager.cpp"
  "native_ui.cpp"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
# NOMINMAX keeps <windows.h> from defining min/max as macros. The plugin used to
# depend on that `max` macro, which meant it only compiled under MSVC and broke
# for any host app that defines NOMINMAX itself (common, since the macros collide
# with std::min/std::max). Defining it here makes a relapse a compile error
# instead of a portability trap. PRIVATE: this is our own translation units only.
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL NOMINMAX)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin Dwmapi Comctl32 Shcore)

# List of absolute paths to libraries that should be bundled with the plugin
set(bitsdojo_window_bundled_libraries
  ""
  PARENT_SCOPE
)
