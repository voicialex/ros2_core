cmake_minimum_required(VERSION 3.10)
project(libyaml_vendor)

if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 17)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)
endif()

find_package(ament_cmake REQUIRED)

list(INSERT CMAKE_MODULE_PATH 0 "${CMAKE_CURRENT_SOURCE_DIR}/cmake/Modules")
find_package(yaml 0.2.5 EXACT QUIET)

macro(build_libyaml)
  set(extra_cmake_args)
  get_property(multi_config GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
  if(NOT multi_config AND DEFINED CMAKE_BUILD_TYPE)
    list(APPEND extra_cmake_args -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
  endif()
  list(APPEND extra_cmake_args -DBUILD_SHARED_LIBS=ON)
  list(APPEND extra_cmake_args -DBUILD_TESTING=OFF)
  list(APPEND extra_cmake_args -DCMAKE_C_FLAGS=${CMAKE_C_FLAGS})
  if(CMAKE_C_COMPILER_ID MATCHES "MSVC")
    set(win_c_flags "${CMAKE_C_FLAGS} /wd4244 /wd4267 /wd4996")
    list(APPEND extra_cmake_args -DCMAKE_C_FLAGS=${win_c_flags})
  endif()
  if(DEFINED CMAKE_TOOLCHAIN_FILE)
    list(APPEND extra_cmake_args "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}")
  endif()

  set(_libyaml_src "${CMAKE_CURRENT_SOURCE_DIR}/libyaml_src")
  if(NOT EXISTS "${_libyaml_src}/cmake/config.h.in")
    message(FATAL_ERROR
      "Vendored libyaml source missing at ${_libyaml_src}. "
      "Run: ./scripts/update_src.sh jazzy")
  endif()

  include(ExternalProject)
  externalproject_add(libyaml-0.2.5
    SOURCE_DIR ${_libyaml_src}
    UPDATE_COMMAND ""
    TIMEOUT 600
    CMAKE_ARGS
      -DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/libyaml_install
      -DINSTALL_INCLUDE_DIR:STRING=include/${PROJECT_NAME}
      ${extra_cmake_args}
    PATCH_COMMAND
      ${CMAKE_COMMAND} -E chdir <SOURCE_DIR> patch -p1 -N --reject-file=/dev/null
        < ${CMAKE_CURRENT_SOURCE_DIR}/0001-Install-yaml.h-to-INSTALL_INCLUDE_DIR.patch || true
  )

  install(
    DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/libyaml_install/
    DESTINATION ${CMAKE_INSTALL_PREFIX}
    USE_SOURCE_PERMISSIONS
    PATTERN config.h EXCLUDE
  )

  set(yaml_INCLUDE_DIRS ${CMAKE_CURRENT_BINARY_DIR}/libyaml_install/include/${PROJECT_NAME})
  set(yaml_LIBRARY_DIRS ${CMAKE_CURRENT_BINARY_DIR}/libyaml_install/lib)
  set(yaml_LIBRARIES yaml)
endmacro()

if(NOT yaml_FOUND)
  build_libyaml()
  set(extra_test_dependencies libyaml-0.2.5)
endif()

ament_export_libraries(yaml)
ament_export_dependencies(yaml)

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  list(APPEND AMENT_LINT_AUTO_EXCLUDE
    ament_cmake_lint_cmake
  )
  ament_lint_auto_find_test_dependencies()
  find_package(ament_cmake_lint_cmake REQUIRED)
  ament_lint_cmake("--filter=-convention/filename,-package/stdargs")

  find_package(ament_cmake_gtest REQUIRED)
  find_package(performance_test_fixture REQUIRED)
  get_target_property(ament_cmake_cppcheck_ADDITIONAL_INCLUDE_DIRS
    performance_test_fixture::performance_test_fixture INTERFACE_INCLUDE_DIRECTORIES)

  ament_add_gtest(test_yaml_reader test/test_reader.cpp
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
  if(TARGET test_yaml_reader)
    target_include_directories(test_yaml_reader PRIVATE ${yaml_INCLUDE_DIRS})
    target_link_libraries(test_yaml_reader ${yaml_LIBRARIES})
    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.13")
      target_link_directories(test_yaml_reader PRIVATE ${yaml_LIBRARY_DIRS})
    endif()
    if(extra_test_dependencies)
      add_dependencies(test_yaml_reader ${extra_test_dependencies})
    endif()
  endif()

  add_performance_test(benchmark_reader test/benchmark/benchmark_reader.cpp
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
  if(TARGET benchmark_reader)
    target_include_directories(benchmark_reader PRIVATE ${yaml_INCLUDE_DIRS})
    target_link_libraries(benchmark_reader ${yaml_LIBRARIES})
    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.13")
      target_link_directories(benchmark_reader PRIVATE ${yaml_LIBRARY_DIRS})
    endif()
    if(extra_test_dependencies)
      add_dependencies(benchmark_reader ${extra_test_dependencies})
    endif()
  endif()
endif()

install(DIRECTORY cmake DESTINATION share/${PROJECT_NAME})
ament_package(CONFIG_EXTRAS libyaml_vendor-extras.cmake)
