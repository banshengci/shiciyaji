#
# Generated file, do not edit.
#
# Flutter tool 会在 `flutter build windows` / `flutter pub get` 时覆盖此文件，
# 写入当前依赖的 Windows 插件实现列表。
#

list(APPEND FLUTTER_PLUGIN_LIST)

set(PLUGIN_BUNDLED_LIBRARIES)

foreach(plugin ${FLUTTER_PLUGIN_LIST})
  add_subdirectory(flutter/ephemeral/.plugin_symlinks/${plugin}/windows plugins/${plugin})
  target_link_libraries(${BINARY_NAME} PRIVATE ${plugin}_plugin)
  list(APPEND PLUGIN_BUNDLED_LIBRARIES $<TARGET_FILE:${plugin}_plugin>)
  list(APPEND PLUGIN_BUNDLED_LIBRARIES ${${plugin}_bundled_libraries})
endforeach(plugin)
