cmake_minimum_required(VERSION 3.5)

project(pybind11_vendor)

find_package(ament_cmake REQUIRED)

option(FORCE_BUILD_VENDOR_PKG
  "Build pybind11 from source, even if system-installed package is available"
  OFF)

if(NOT FORCE_BUILD_VENDOR_PKG)
  find_package(pybind11 QUIET)
endif()

macro(build_pybind11)
  set(extra_cmake_args)

  if(DEFINED CMAKE_TOOLCHAIN_FILE)
    list(APPEND extra_cmake_args "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}")
  else()
    list(APPEND extra_cmake_args "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}")
  endif()
  list(APPEND extra_cmake_args "-DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}")

  set(_pybind11_src "${CMAKE_CURRENT_SOURCE_DIR}/pybind11_src")
  if(NOT EXISTS "${_pybind11_src}/CMakeLists.txt")
    message(FATAL_ERROR
      "Vendored pybind11 source missing at ${_pybind11_src}. "
      "Run: ./scripts/update_src.sh humble")
  endif()

  include(ExternalProject)
  externalproject_add(pybind11-2.9.1
    SOURCE_DIR ${_pybind11_src}
    UPDATE_COMMAND ""
    TIMEOUT 300
    CMAKE_ARGS
      -DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}_install
      -DPYBIND11_TEST=OFF
      -DCMAKE_INSTALL_INCLUDEDIR=include/${PROJECT_NAME}
      ${extra_cmake_args}
    PATCH_COMMAND
      ${CMAKE_COMMAND} -E chdir <SOURCE_DIR> patch -p1 -N --reject-file=/dev/null
        < ${CMAKE_CURRENT_SOURCE_DIR}/pybind11-2.9.1-fix-windows-debug.patch || true
  )

  install(
    DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}_install/
    DESTINATION ${CMAKE_INSTALL_PREFIX}
    USE_SOURCE_PERMISSIONS
  )
endmacro()

if(FORCE_BUILD_VENDOR_PKG OR NOT pybind11_FOUND)
  build_pybind11()
endif()

ament_package()
