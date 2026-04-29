# Minimal C++ ROS2 Repos Design

Date: 2026-04-29

## Goal

Slim ros2_core to the minimum repos needed for a pure C++ ROS2 stack (rclcpp_components, rclcpp_lifecycle, std_msgs, sensor_msgs, builtin_interfaces, rosidl_default_generators) with FastDDS only. Make update_src.sh declaratively sync src/ from .repos, and fix the tracetools LTTng build error.

## Decisions

- Pure C++, no Python (rclpy, rosidl_python, pybind11 etc. removed)
- No URDF/tf2/KDL (urdf, geometry2, kdl_parser etc. removed)
- No launch system (launch, launch_ros removed)
- No test/lint packages (googletest, ament_lint, mimick_vendor etc. removed)
- `.repos` is the single source of truth for src/<distro>/
- src/ not committed to git (.gitignore), .git dirs preserved for incremental vcs pull
- tracetools kept but LTTng disabled via `-DTRACETOOLS_DISABLED=ON`

## File Changes

### repos/humble.repos — ~55 → 26 repos

```yaml
repositories:
  # Build system (5)
  ament/ament_cmake:
    type: git
    url: https://github.com/ament/ament_cmake.git
    version: humble
  ament/ament_index:
    type: git
    url: https://github.com/ament/ament_index.git
    version: humble
  ament/ament_package:
    type: git
    url: https://github.com/ament/ament_package.git
    version: humble
  ros2/ament_cmake_ros:
    type: git
    url: https://github.com/ros2/ament_cmake_ros.git
    version: humble
  ros/ros_environment:
    type: git
    url: https://github.com/ros/ros_environment.git
    version: humble

  # Middleware (3)
  eProsima/Fast-CDR:
    type: git
    url: https://github.com/eProsima/Fast-CDR.git
    version: v1.0.24
  eProsima/Fast-DDS:
    type: git
    url: https://github.com/eProsima/Fast-DDS.git
    version: 2.6.x
  eProsima/foonathan_memory_vendor:
    type: git
    url: https://github.com/eProsima/foonathan_memory_vendor.git
    version: master

  # ROS2 core (12)
  ros2/rcutils:
    type: git
    url: https://github.com/ros2/rcutils.git
    version: humble
  ros2/rcpputils:
    type: git
    url: https://github.com/ros2/rcpputils.git
    version: humble
  ros2/rcl:
    type: git
    url: https://github.com/ros2/rcl.git
    version: humble
  ros2/rcl_logging:
    type: git
    url: https://github.com/ros2/rcl_logging.git
    version: humble
  ros2/rclcpp:
    type: git
    url: https://github.com/ros2/rclcpp.git
    version: humble
  ros2/rmw:
    type: git
    url: https://github.com/ros2/rmw.git
    version: humble
  ros2/rmw_dds_common:
    type: git
    url: https://github.com/ros2/rmw_dds_common.git
    version: humble
  ros2/rmw_fastrtps:
    type: git
    url: https://github.com/ros2/rmw_fastrtps.git
    version: humble
  ros2/rmw_implementation:
    type: git
    url: https://github.com/ros2/rmw_implementation.git
    version: humble
  ros2/ros2_tracing:
    type: git
    url: https://github.com/ros2/ros2_tracing.git
    version: humble
  ros-tooling/libstatistics_collector:
    type: git
    url: https://github.com/ros-tooling/libstatistics_collector.git
    version: humble
  ros/class_loader:
    type: git
    url: https://github.com/ros/class_loader.git
    version: humble

  # Vendor packages (6)
  ros2/spdlog_vendor:
    type: git
    url: https://github.com/ros2/spdlog_vendor.git
    version: humble
  ros2/libyaml_vendor:
    type: git
    url: https://github.com/ros2/libyaml_vendor.git
    version: humble
  ros2/yaml_cpp_vendor:
    type: git
    url: https://github.com/ros2/yaml_cpp_vendor.git
    version: humble
  ros2/tinyxml2_vendor:
    type: git
    url: https://github.com/ros2/tinyxml2_vendor.git
    version: humble
  ros2/tinyxml_vendor:
    type: git
    url: https://github.com/ros2/tinyxml_vendor.git
    version: humble
  ros2/console_bridge_vendor:
    type: git
    url: https://github.com/ros2/console_bridge_vendor.git
    version: humble

  # IDL & messages (7)
  ros2/rosidl:
    type: git
    url: https://github.com/ros2/rosidl.git
    version: humble
  ros2/rosidl_defaults:
    type: git
    url: https://github.com/ros2/rosidl_defaults.git
    version: humble
  ros2/rosidl_typesupport:
    type: git
    url: https://github.com/ros2/rosidl_typesupport.git
    version: humble
  ros2/rosidl_typesupport_fastrtps:
    type: git
    url: https://github.com/ros2/rosidl_typesupport_fastrtps.git
    version: humble
  ros2/rcl_interfaces:
    type: git
    url: https://github.com/ros2/rcl_interfaces.git
    version: humble
  ros2/common_interfaces:
    type: git
    url: https://github.com/ros2/common_interfaces.git
    version: humble
  ros2/unique_identifier_msgs:
    type: git
    url: https://github.com/ros2/unique_identifier_msgs.git
    version: humble
```

### repos/jazzy.repos — ~60 → 28 repos

Same structure as humble but with:
- `version: jazzy` (except eProsima: Fast-CDR `2.2.x`, Fast-DDS `2.14.x`, foonathan `master`)
- No `tinyxml_vendor` (Jazzy dropped tinyxml1 dependency)
- Added: `ros2/rosidl_core` (Jazzy split from rosidl_defaults)
- Added: `ros2/rosidl_dynamic_typesupport` (Jazzy rcl dependency)
- Added: `ros2/rosidl_dynamic_typesupport_fastrtps` (Jazzy rmw_fastrtps dependency)

### scripts/update_src.sh — declarative sync

Logic:
1. Parse .repos: `grep` lines matching `^  [a-zA-Z]` to extract repo paths
2. List existing dirs in src/<distro>/ at two levels deep (org/repo)
3. Delete dirs present on disk but absent from .repos
4. `vcs import` to pull/update (preserves .git for incremental updates)
5. Report added/removed/total counts

No .git cleanup. No EXCLUDED_REPOS hardcoded list.

### scripts/build.sh — minor fixes

1. Add `-DTRACETOOLS_DISABLED=ON` to cmake args
2. Remove package count check (lines 80-85, was "expected 80+")
3. Keep asio header check
4. Everything else unchanged

### .gitignore — add src/

Add `src/` to ignore vendored source trees (they have .git dirs and are pulled on demand).

## Removed Repos Summary

| Category | Count | Examples |
|---|---|---|
| Python | 7 | rclpy, rosidl_python, pybind11_vendor, rpyutils, python_cmake_module, osrf_pycommon, rosidl_runtime_py |
| Test/Lint | 7 | ament_lint, googletest, google_benchmark_vendor, uncrustify_vendor, osrf_testing_tools_cpp, mimick_vendor, performance_test_fixture, test_interface_files |
| URDF/KDL | 9 | urdfdom, urdfdom_headers, urdf, kdl_parser, orocos_kdl_vendor, robot_state_publisher, pluginlib, resource_retriever, eigen3_cmake_module |
| Launch | 2 | launch, launch_ros |
| Other | ~8 | image_common, keyboard_handler, geometry2, message_filters, realtime_support, rosidl_rust, rosidl_dds, pybind11_vendor |

## Risks

1. Hidden transitive dependency missing — mitigated by compiling immediately after change and adding back any missing repo
2. Jazzy rosidl_core/dynamic_typesupport might not be needed — verify by trying without first
3. `vcs import` without `--skip-existing` will fail on existing repos — must use `--skip-existing` flag
