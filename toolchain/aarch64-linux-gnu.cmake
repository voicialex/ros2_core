# toolchain/aarch64-linux-gnu.cmake
# Cross-compilation toolchain for aarch64 (ARM64) targets.
# Usage: colcon build --cmake-args -DCMAKE_TOOLCHAIN_FILE=<this-file>

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

# Pre-filled TRY_RUN results (target binaries can't execute on host)
include("${CMAKE_CURRENT_LIST_DIR}/aarch64-tryrun-results.cmake")

# Cross-compiled Python — hint FindPythonLibs (used by rosidl_generator_py)
execute_process(
  COMMAND python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
  OUTPUT_VARIABLE _py_ver
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
set(PYTHON_INCLUDE_DIR "/usr/include/python${_py_ver}" CACHE PATH "Python include directory (target arch)")
set(PYTHON_LIBRARY "/usr/lib/${CMAKE_SYSTEM_PROCESSOR}-linux-gnu/libpython${_py_ver}.so" CACHE FILEPATH "Python library (target arch)")
# Jazzy+FindPython3 hints (CMake >=3.28 uses FindPython3 via rosidl_generator_py)
set(Python3_INCLUDE_DIR "/usr/include/python${_py_ver}" CACHE PATH "Python3 include directory (target arch)")
set(Python3_LIBRARY "/usr/lib/${CMAKE_SYSTEM_PROCESSOR}-linux-gnu/libpython${_py_ver}.so" CACHE FILEPATH "Python3 library (target arch)")

# CMake packages invoke the host interpreter to discover the extension suffix.
# Override it because target Python extensions must be importable by aarch64 Python.
string(REPLACE "." "" _py_abi_ver "${_py_ver}")
set(_py_soabi "cpython-${_py_abi_ver}-${CMAKE_SYSTEM_PROCESSOR}-linux-gnu")
set(PYTHON_SOABI "${_py_soabi}" CACHE INTERNAL "Target Python extension ABI" FORCE)
set(PythonExtra_EXTENSION_SUFFIX ".${_py_soabi}" CACHE INTERNAL "Target Python extension suffix" FORCE)
set(PYTHON_MODULE_EXTENSION ".${_py_soabi}.so" CACHE INTERNAL "Target pybind11 extension suffix" FORCE)
unset(_py_abi_ver)
unset(_py_soabi)
unset(_py_ver)
