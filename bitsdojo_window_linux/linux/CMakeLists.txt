cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "bitsdojo_window_linux")
project(${PROJECT_NAME} LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

add_library(${PLUGIN_NAME} SHARED
  "debug_helper.cpp"
  "api_impl.cpp"
  "multi_window_manager.cpp"
  "bitsdojo_window_plugin.cpp"
  "window_impl.cpp"
  "window_info.cpp"
  "gtk_utils.cpp"
  "api.cpp"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK)

set(bitsdojo_window_bundled_libraries
  ""
  PARENT_SCOPE
)
