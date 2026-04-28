cmake_minimum_required(VERSION 3.13)
project(console_bridge_vendor)

if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 17)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)
endif()

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)

option(FORCE_BUILD_VENDOR_PKG
  "Build console_bridge from source, even if system-installed package is available"
  OFF)

if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()

if(NOT FORCE_BUILD_VENDOR_PKG)
  find_package(console_bridge 1.0.1 QUIET)
endif()

macro(build_console_bridge)
  include(GNUInstallDirs)
  set(extra_cmake_args
    "-DCMAKE_INSTALL_LIBDIR=${CMAKE_INSTALL_LIBDIR}"
    "-DCMAKE_INSTALL_INCLUDEDIR=${CMAKE_INSTALL_INCLUDEDIR}/${PROJECT_NAME}"
  )
  if(DEFINED CMAKE_BUILD_TYPE)
    list(APPEND extra_cmake_args -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
  endif()
  if(DEFINED CMAKE_TOOLCHAIN_FILE)
    list(APPEND extra_cmake_args "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}")
  else()
    list(APPEND extra_cmake_args "-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}")
    list(APPEND extra_cmake_args "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}")
  endif()
  list(APPEND extra_cmake_args "-DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}")

  set(_console_bridge_src "${CMAKE_CURRENT_SOURCE_DIR}/console_bridge_src")
  if(NOT EXISTS "${_console_bridge_src}/CMakeLists.txt")
    message(FATAL_ERROR
      "Vendored console_bridge source missing at ${_console_bridge_src}. "
      "Run: ./scripts/update_src.sh jazzy")
  endif()

  include(ExternalProject)
  externalproject_add(console_bridge-1.0.2
    SOURCE_DIR ${_console_bridge_src}
    UPDATE_COMMAND ""
    TIMEOUT 600
    CMAKE_ARGS
      -DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}_install
      ${extra_cmake_args}
      -Wno-dev
  )

  install(
    DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}_install/
    DESTINATION ${CMAKE_INSTALL_PREFIX}
    USE_SOURCE_PERMISSIONS
  )

  set(console_bridge_INCLUDE_DIRS
    ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}_install/${CMAKE_INSTALL_INCLUDEDIR}/${PROJECT_NAME})
  set(console_bridge_LIBRARY_DIRS
    ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}_install/${CMAKE_INSTALL_LIBDIR})
  set(console_bridge_LIBRARIES console_bridge)
endmacro()

if(FORCE_BUILD_VENDOR_PKG OR NOT console_bridge_FOUND OR "${console_bridge_VERSION}" VERSION_LESS 1.0.1)
  build_console_bridge()
  set(extra_test_dependencies console_bridge-1.0.2)
endif()

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()

  find_package(performance_test_fixture REQUIRED)
  get_target_property(ament_cmake_cppcheck_ADDITIONAL_INCLUDE_DIRS
    performance_test_fixture::performance_test_fixture INTERFACE_INCLUDE_DIRECTORIES)

  add_performance_test(benchmark_log test/benchmark/benchmark_log.cpp)
  if(TARGET benchmark_log)
    target_include_directories(benchmark_log PRIVATE ${console_bridge_INCLUDE_DIRS})
    target_link_libraries(benchmark_log ${console_bridge_LIBRARIES})
    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.13")
      target_link_directories(benchmark_log PRIVATE ${console_bridge_LIBRARY_DIRS})
    endif()
    if(extra_test_dependencies)
      add_dependencies(benchmark_log ${extra_test_dependencies})
    endif()
  endif()
endif()

ament_package()
