cmake_minimum_required(VERSION 3.5)

project(tinyxml2_vendor)

find_package(ament_cmake REQUIRED)

option(FORCE_BUILD_VENDOR_PKG
  "Build tinyxml2 from source, even if system-installed package is available"
  OFF)

list(INSERT CMAKE_MODULE_PATH 0 "${CMAKE_CURRENT_SOURCE_DIR}/cmake/Modules")

if(NOT FORCE_BUILD_VENDOR_PKG)
  find_package(TinyXML2 QUIET)
endif()

macro(build_tinyxml2)
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

  include(ExternalProject)

  set(_tinyxml2_src "${CMAKE_CURRENT_SOURCE_DIR}/tinyxml2_src")
  if(NOT EXISTS "${_tinyxml2_src}/CMakeLists.txt")
    message(FATAL_ERROR
      "Vendored tinyxml2 source missing at ${_tinyxml2_src}. "
      "Run: ./scripts/update_src.sh humble")
  endif()

  externalproject_add(tinyxml2-9.0.0
    SOURCE_DIR ${_tinyxml2_src}
    UPDATE_COMMAND ""
    TIMEOUT 600
    CMAKE_ARGS
      -DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}_install
      -DBUILD_SHARED_LIBS=ON
      -Dtinyxml2_BUILD_TESTING=OFF
      ${extra_cmake_args}
  )

  install(
    DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}_install/
    DESTINATION ${CMAKE_INSTALL_PREFIX}
    USE_SOURCE_PERMISSIONS
  )
endmacro()

if(FORCE_BUILD_VENDOR_PKG OR NOT TinyXML2_FOUND)
  build_tinyxml2()
endif()

install(DIRECTORY cmake DESTINATION share/${PROJECT_NAME})

ament_package(
  CONFIG_EXTRAS "tinyxml2_vendor-extras.cmake"
)
