cmake_minimum_required(VERSION 3.10)
project(spdlog_vendor CXX)

find_package(ament_cmake REQUIRED)

if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()

option(FORCE_BUILD_VENDOR_PKG
  "Build spdlog from source, even if system-installed package is available"
  OFF)

if(NOT FORCE_BUILD_VENDOR_PKG)
  find_package(spdlog 1.5.0 QUIET)
endif()

set(BUILD_SHARED_LIBS TRUE CACHE BOOL "Build shared libraries")

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  set(CMAKE_CXX_FLAGS "-Wno-deprecated-declarations ${CMAKE_CXX_FLAGS}")
endif()

macro(build_spdlog)
  set(extra_cmake_args)
  if(DEFINED CMAKE_BUILD_TYPE)
    list(APPEND extra_cmake_args -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
  endif()
  if(DEFINED CMAKE_TOOLCHAIN_FILE)
    list(APPEND extra_cmake_args "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}")
  else()
    list(APPEND extra_cmake_args "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}")
  endif()
  list(APPEND extra_cmake_args "-DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}")
  list(APPEND extra_cmake_args "-DSPDLOG_BUILD_TESTS=OFF")
  list(APPEND extra_cmake_args "-DSPDLOG_BUILD_EXAMPLE=OFF")
  if(NOT WIN32)
    list(APPEND extra_cmake_args "-DSPDLOG_BUILD_SHARED=ON")
  endif()

  set(_spdlog_src "${CMAKE_CURRENT_SOURCE_DIR}/spdlog_src")
  if(NOT EXISTS "${_spdlog_src}/CMakeLists.txt")
    message(FATAL_ERROR
      "Vendored spdlog source missing at ${_spdlog_src}. "
      "Run: ./scripts/update_src.sh jazzy")
  endif()

  include(ExternalProject)
  externalproject_add(spdlog-1.12.0
    SOURCE_DIR ${_spdlog_src}
    UPDATE_COMMAND ""
    TIMEOUT 600
    CMAKE_ARGS
      -DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}_install
      ${extra_cmake_args}
  )

  install(
    DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}_install/
    DESTINATION ${CMAKE_INSTALL_PREFIX}
    USE_SOURCE_PERMISSIONS
  )
endmacro()

if(FORCE_BUILD_VENDOR_PKG OR NOT spdlog_FOUND OR "${spdlog_VERSION}" VERSION_LESS 1.5.0)
  build_spdlog()
endif()

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  list(APPEND AMENT_LINT_AUTO_EXCLUDE ament_cmake_cppcheck)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
