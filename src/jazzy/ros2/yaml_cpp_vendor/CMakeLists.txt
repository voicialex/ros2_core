cmake_minimum_required(VERSION 3.10)
project(yaml_cpp_vendor CXX)

find_package(ament_cmake REQUIRED)

if(POLICY CMP0135)
  cmake_policy(SET CMP0135 OLD)
endif()

option(FORCE_BUILD_VENDOR_PKG
  "Build yaml-cpp from source, even if system-installed package is available"
  OFF)

find_package(yaml-cpp 0.8.0 QUIET NO_CMAKE_PACKAGE_REGISTRY)

set(YAML_CPP_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
if(MSVC)
  set(YAML_CPP_CXX_FLAGS "/wd4251 /wd4275 ${YAML_CPP_CXX_FLAGS}")
endif()

macro(build_yaml_cpp)
  set(extra_cmake_args)
  if(DEFINED CMAKE_BUILD_TYPE)
    list(APPEND extra_cmake_args -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
  endif()
  if(NOT WIN32)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -w")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -w")
  endif()
  list(APPEND extra_cmake_args "-DYAML_CPP_BUILD_TESTS=OFF")
  list(APPEND extra_cmake_args "-DYAML_CPP_BUILD_TOOLS=OFF")
  list(APPEND extra_cmake_args "-DYAML_CPP_BUILD_CONTRIB=OFF")
  list(APPEND extra_cmake_args "-DYAML_BUILD_SHARED_LIBS=ON")
  list(APPEND extra_cmake_args "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}")
  list(APPEND extra_cmake_args "-DCMAKE_CXX_FLAGS=${YAML_CPP_CXX_FLAGS}")
  if(DEFINED CMAKE_TOOLCHAIN_FILE)
    list(APPEND extra_cmake_args "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}")
  endif()

  set(_yaml_cpp_src "${CMAKE_CURRENT_SOURCE_DIR}/yaml_cpp_src")
  if(NOT EXISTS "${_yaml_cpp_src}/CMakeLists.txt")
    message(FATAL_ERROR
      "Vendored yaml-cpp source missing at ${_yaml_cpp_src}. "
      "Run: ./scripts/update_src.sh jazzy")
  endif()

  include(ExternalProject)
  externalproject_add(yaml_cpp-0.8.0
    SOURCE_DIR ${_yaml_cpp_src}
    UPDATE_COMMAND ""
    TIMEOUT 600
    CMAKE_ARGS
      -DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/yaml_cpp_install
      ${extra_cmake_args}
      -Wno-dev
    PATCH_COMMAND
      ${CMAKE_COMMAND} -E chdir <SOURCE_DIR> patch -p1 -N --reject-file=/dev/null
        < ${CMAKE_CURRENT_SOURCE_DIR}/patches/0001.patch || true
  )

  install(
    DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/yaml_cpp_install/
    DESTINATION ${CMAKE_INSTALL_PREFIX}/opt/yaml_cpp_vendor
    USE_SOURCE_PERMISSIONS
  )
endmacro()

if(FORCE_BUILD_VENDOR_PKG OR NOT yaml-cpp_FOUND)
  build_yaml_cpp()
  if(WIN32)
    ament_environment_hooks(env_hook/yaml_cpp_vendor_library_path.bat)
    set(ENV_VAR_NAME "PATH")
    set(ENV_VAR_VALUE "opt\\yaml_cpp_vendor\\bin")
  else()
    ament_environment_hooks(env_hook/yaml_cpp_vendor_library_path.sh)
    if(APPLE)
      set(ENV_VAR_NAME "DYLD_LIBRARY_PATH")
    else()
      set(ENV_VAR_NAME "LD_LIBRARY_PATH")
    endif()
    set(ENV_VAR_VALUE "opt/yaml_cpp_vendor/lib")
  endif()
  ament_environment_hooks(env_hook/yaml_cpp_vendor_library_path.dsv.in)
else()
  message(STATUS "Found yaml-cpp ${yaml-cpp_VERSION} in path ${yaml-cpp_CONFIG}")
endif()

ament_package(CONFIG_EXTRAS "yaml_cpp_vendor-extras.cmake.in")
