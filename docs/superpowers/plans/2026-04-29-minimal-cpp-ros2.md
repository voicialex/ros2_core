# Minimal C++ ROS2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Slim ros2_core to ~26 repos (humble) / ~28 repos (jazzy) for a pure C++ ROS2 stack, with declarative source sync and fixed tracetools build.

**Architecture:** Replace bloated .repos files with minimal sets, rewrite update_src.sh as a declarative sync tool driven by .repos as single source of truth, patch build.sh to disable LTTng, and stop committing vendored sources to git.

**Tech Stack:** Bash, vcstool, colcon, CMake

---

### Task 1: Update .gitignore to exclude src/

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add src/ to .gitignore**

Replace the existing `src/` partial ignores with a blanket `src/` entry. The current file is:

```
# Build artifacts
src/*/build/
src/*/install/
src/*/log/

# Output
dist/
output/
*.tar.gz
```

Replace with:

```
# Vendored ROS2 sources (pulled by scripts/update_src.sh)
src/

# Output
dist/
output/
*.tar.gz
```

- [ ] **Step 2: Remove src/ from git tracking (if tracked)**

Run:
```bash
git rm -r --cached src/ 2>/dev/null || true
```

This untracks the files without deleting them from disk.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "feat(module): [PRO-10000] Stop tracking vendored src/ in git"
```

---

### Task 2: Replace repos/humble.repos with minimal set

**Files:**
- Modify: `repos/humble.repos`

- [ ] **Step 1: Overwrite humble.repos**

Replace the entire file with this content (26 repos):

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

- [ ] **Step 2: Verify repo count**

Run:
```bash
grep -c "type: git" repos/humble.repos
```

Expected: `26`

- [ ] **Step 3: Commit**

```bash
git add repos/humble.repos
git commit -m "feat(module): [PRO-10000] Slim humble.repos to 26 minimal C++ repos"
```

---

### Task 3: Replace repos/jazzy.repos with minimal set

**Files:**
- Modify: `repos/jazzy.repos`

- [ ] **Step 1: Overwrite jazzy.repos**

Replace the entire file with this content (28 repos — humble set minus tinyxml_vendor, plus rosidl_core + 2 dynamic_typesupport):

```yaml
repositories:
  # Build system (5)
  ament/ament_cmake:
    type: git
    url: https://github.com/ament/ament_cmake.git
    version: jazzy
  ament/ament_index:
    type: git
    url: https://github.com/ament/ament_index.git
    version: jazzy
  ament/ament_package:
    type: git
    url: https://github.com/ament/ament_package.git
    version: jazzy
  ros2/ament_cmake_ros:
    type: git
    url: https://github.com/ros2/ament_cmake_ros.git
    version: jazzy
  ros/ros_environment:
    type: git
    url: https://github.com/ros/ros_environment.git
    version: jazzy

  # Middleware (3)
  eProsima/Fast-CDR:
    type: git
    url: https://github.com/eProsima/Fast-CDR.git
    version: 2.2.x
  eProsima/Fast-DDS:
    type: git
    url: https://github.com/eProsima/Fast-DDS.git
    version: 2.14.x
  eProsima/foonathan_memory_vendor:
    type: git
    url: https://github.com/eProsima/foonathan_memory_vendor.git
    version: master

  # ROS2 core (12)
  ros2/rcutils:
    type: git
    url: https://github.com/ros2/rcutils.git
    version: jazzy
  ros2/rcpputils:
    type: git
    url: https://github.com/ros2/rcpputils.git
    version: jazzy
  ros2/rcl:
    type: git
    url: https://github.com/ros2/rcl.git
    version: jazzy
  ros2/rcl_logging:
    type: git
    url: https://github.com/ros2/rcl_logging.git
    version: jazzy
  ros2/rclcpp:
    type: git
    url: https://github.com/ros2/rclcpp.git
    version: jazzy
  ros2/rmw:
    type: git
    url: https://github.com/ros2/rmw.git
    version: jazzy
  ros2/rmw_dds_common:
    type: git
    url: https://github.com/ros2/rmw_dds_common.git
    version: jazzy
  ros2/rmw_fastrtps:
    type: git
    url: https://github.com/ros2/rmw_fastrtps.git
    version: jazzy
  ros2/rmw_implementation:
    type: git
    url: https://github.com/ros2/rmw_implementation.git
    version: jazzy
  ros2/ros2_tracing:
    type: git
    url: https://github.com/ros2/ros2_tracing.git
    version: jazzy
  ros-tooling/libstatistics_collector:
    type: git
    url: https://github.com/ros-tooling/libstatistics_collector.git
    version: jazzy
  ros/class_loader:
    type: git
    url: https://github.com/ros/class_loader.git
    version: jazzy

  # Vendor packages (5, no tinyxml_vendor in Jazzy)
  ros2/spdlog_vendor:
    type: git
    url: https://github.com/ros2/spdlog_vendor.git
    version: jazzy
  ros2/libyaml_vendor:
    type: git
    url: https://github.com/ros2/libyaml_vendor.git
    version: jazzy
  ros2/yaml_cpp_vendor:
    type: git
    url: https://github.com/ros2/yaml_cpp_vendor.git
    version: jazzy
  ros2/tinyxml2_vendor:
    type: git
    url: https://github.com/ros2/tinyxml2_vendor.git
    version: jazzy
  ros2/console_bridge_vendor:
    type: git
    url: https://github.com/ros2/console_bridge_vendor.git
    version: jazzy

  # IDL & messages (10, Jazzy adds rosidl_core + dynamic_typesupport)
  ros2/rosidl:
    type: git
    url: https://github.com/ros2/rosidl.git
    version: jazzy
  ros2/rosidl_core:
    type: git
    url: https://github.com/ros2/rosidl_core.git
    version: jazzy
  ros2/rosidl_defaults:
    type: git
    url: https://github.com/ros2/rosidl_defaults.git
    version: jazzy
  ros2/rosidl_dynamic_typesupport:
    type: git
    url: https://github.com/ros2/rosidl_dynamic_typesupport.git
    version: jazzy
  ros2/rosidl_dynamic_typesupport_fastrtps:
    type: git
    url: https://github.com/ros2/rosidl_dynamic_typesupport_fastrtps.git
    version: jazzy
  ros2/rosidl_typesupport:
    type: git
    url: https://github.com/ros2/rosidl_typesupport.git
    version: jazzy
  ros2/rosidl_typesupport_fastrtps:
    type: git
    url: https://github.com/ros2/rosidl_typesupport_fastrtps.git
    version: jazzy
  ros2/rcl_interfaces:
    type: git
    url: https://github.com/ros2/rcl_interfaces.git
    version: jazzy
  ros2/common_interfaces:
    type: git
    url: https://github.com/ros2/common_interfaces.git
    version: jazzy
  ros2/unique_identifier_msgs:
    type: git
    url: https://github.com/ros2/unique_identifier_msgs.git
    version: jazzy
```

- [ ] **Step 2: Verify repo count**

Run:
```bash
grep -c "type: git" repos/jazzy.repos
```

Expected: `28`

- [ ] **Step 3: Commit**

```bash
git add repos/jazzy.repos
git commit -m "feat(module): [PRO-10000] Slim jazzy.repos to 28 minimal C++ repos"
```

---

### Task 4: Rewrite scripts/update_src.sh as declarative sync

**Files:**
- Modify: `scripts/update_src.sh`

- [ ] **Step 1: Replace update_src.sh**

Overwrite the entire file with:

```bash
#!/usr/bin/env bash
# update_src.sh — declaratively sync src/<distro>/ from repos/<distro>.repos
set -euo pipefail

DISTRO="${1:?用法: $0 humble|jazzy}"
case "$DISTRO" in
    humble|jazzy) ;;
    *) echo "错误: distro 必须是 humble 或 jazzy"; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_FILE="$REPO_ROOT/repos/${DISTRO}.repos"
SRC_DIR="$REPO_ROOT/src/$DISTRO"

if [ ! -f "$REPOS_FILE" ]; then
    echo "错误: repos 文件不存在: $REPOS_FILE"; exit 1
fi

if ! command -v vcs &>/dev/null; then
    pip3 install --break-system-packages vcstool
fi

mkdir -p "$SRC_DIR"

# Parse wanted repo paths from .repos (e.g. "ament/ament_cmake")
WANTED=$(grep -E '^ {2}[a-zA-Z]' "$REPOS_FILE" | sed 's/: *$//' | tr -d ' ')

# Remove directories not in .repos
if [ -d "$SRC_DIR" ]; then
    for org_dir in "$SRC_DIR"/*/; do
        [ -d "$org_dir" ] || continue
        org=$(basename "$org_dir")
        for repo_dir in "$org_dir"/*/; do
            [ -d "$repo_dir" ] || continue
            repo=$(basename "$repo_dir")
            path="$org/$repo"
            if ! echo "$WANTED" | grep -qx "$path"; then
                echo "[INFO] 移除不在 .repos 中的仓库: $path"
                rm -rf "$repo_dir"
            fi
        done
        # Remove empty org dir
        rmdir "$org_dir" 2>/dev/null || true
    done
fi

# Pull/update repos
echo "[INFO] 同步 $DISTRO 源码..."
vcs import --skip-existing "$SRC_DIR" < "$REPOS_FILE"

COUNT=$(echo "$WANTED" | wc -l)
echo "[OK] 已同步 $COUNT 个仓库到 src/$DISTRO"
```

- [ ] **Step 2: Verify script is executable**

Run:
```bash
chmod +x scripts/update_src.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/update_src.sh
git commit -m "feat(module): [PRO-10000] Rewrite update_src.sh as declarative sync"
```

---

### Task 5: Patch scripts/build.sh

**Files:**
- Modify: `scripts/build.sh`

- [ ] **Step 1: Add -DTRACETOOLS_DISABLED=ON to cmake args**

In `scripts/build.sh`, find line 158:

```bash
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
```

Replace with:

```bash
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DTRACETOOLS_DISABLED=ON \
```

- [ ] **Step 2: Remove package count check (lines 80-85)**

Find and delete these lines:

```bash
PKG_COUNT="$(find "$SRC_DIR" -name "package.xml" | wc -l)"
if [ "$PKG_COUNT" -lt 10 ]; then
    echo "错误: 源码不完整，只找到 $PKG_COUNT 个包（预期 80+）"
    echo "请重新拉取: rm -rf src/$DISTRO && ./scripts/update_src.sh $DISTRO"
    exit 1
fi
```

- [ ] **Step 3: Commit**

```bash
git add scripts/build.sh
git commit -m "feat(module): [PRO-10000] Disable LTTng tracing and remove stale pkg count check"
```
