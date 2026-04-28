# toolchain/aarch64-linux-gnu.cmake
# Cross-compilation toolchain for aarch64 (ARM64) targets
# Used by: colcon build --cmake-args -DCMAKE_TOOLCHAIN_FILE=<this file>
#
# NOTE: We keep CMAKE_FIND_ROOT_PATH_MODE settings relaxed because colcon
# builds packages incrementally and sets CMAKE_PREFIX_PATH via env var.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)

set(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE NEVER)

# Preserve CMAKE_PREFIX_PATH from environment (colcon sets this per-package)
if(DEFINED ENV{CMAKE_PREFIX_PATH})
  string(REPLACE ":" ";" _env_prefix "$ENV{CMAKE_PREFIX_PATH}")
  list(APPEND CMAKE_PREFIX_PATH ${_env_prefix})
endif()

# Ensure PIC for shared libraries
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
