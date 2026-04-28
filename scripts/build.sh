#!/usr/bin/env bash
# build.sh — 从源码编译 ROS2 核心并打包为自包含 tarball
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── 功能开关 (改为 false 跳过对应模块) ───
ENABLE_VISION=true
ENABLE_CLI=true

# ─── 编译目标包 (core) ───
TARGET_PKGS=(
  rclcpp_components rclcpp_lifecycle
  rclcpp_action rcl_action action_msgs
  std_msgs sensor_msgs builtin_interfaces
  rosidl_default_generators
  yaml_cpp_vendor
)

# ─── vision 模块包 ───
VISION_PKGS=(
  cv_bridge image_transport v4l2_camera
)

# ─── CLI 工具包 ───
CLI_PKGS=(
  ros2cli ros2topic ros2node ros2service ros2param ros2interface
  rclpy rosidl_runtime_py
)

# ─── 要跳过的测试包 ───
SKIP_PKGS=(test_msgs test_interface_files ros2cli_test_interfaces)

# ─── 函数定义 ───

usage() {
  cat <<'EOF'
用法: ./scripts/build.sh <distro> [选项]

从源码编译 ROS2 核心并打包为自包含 tarball。

参数:
  distro                 humble 或 jazzy

选项:
  -t, --arch ARCH        目标架构: x86_64 (默认) 或 arm64/aarch64
  -o, --output DIR       输出目录 (默认: <repo>/output/<distro>)
  -c, --clean            清除编译缓存，全量重新编译
  -h, --help             显示帮助

示例:
  ./scripts/build.sh humble
  ./scripts/build.sh humble --arch arm64
  ./scripts/build.sh humble -c

Docker 编译 (推荐干净环境):
  ./scripts/docker_build.sh <distro> [选项]
  Dockerfile 或 base 镜像变更后加 --no-cache 强制重建 base，例如:
  ./scripts/docker_build.sh humble --no-cache
EOF
}

parse_args() {
  DISTRO=""
  OUTPUT_DIR=""
  CLEAN_BUILD=false
  TARGET_ARCH="$(uname -m)"

  while [ $# -gt 0 ]; do
    case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -o | --output)
      OUTPUT_DIR="${2:?缺少输出目录}"
      shift 2
      ;;
    -c | --clean)
      CLEAN_BUILD=true
      shift
      ;;
    -t | --arch)
      TARGET_ARCH="${2:?缺少架构}"
      shift 2
      ;;
    humble | jazzy)
      DISTRO="$1"
      shift
      ;;
    *)
      echo "未知参数: $1"
      usage
      exit 1
      ;;
    esac
  done

  if [ -z "$DISTRO" ]; then
    echo "错误: 必须指定 distro (humble 或 jazzy)"
    usage
    exit 1
  fi

  # Normalize arch names
  case "$TARGET_ARCH" in
    arm64|aarch64) TARGET_ARCH="aarch64" ;;
    x86_64|x86|amd64) TARGET_ARCH="x86_64" ;;
    *) echo "错误: 不支持的架构: $TARGET_ARCH"; exit 1 ;;
  esac

  OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output/$DISTRO}"
  SRC_DIR="$REPO_ROOT/src/$DISTRO"
}

preflight_check() {
  if [ ! -d "$SRC_DIR" ]; then
    echo "错误: 源码目录不存在: $SRC_DIR"
    echo "请先运行: ./scripts/update_src.sh $DISTRO"
    exit 1
  fi

  # Cross-compile: check OpenSSL headers for target arch
  if [ "$TARGET_ARCH" != "$(uname -m)" ]; then
    echo "[INFO] 交叉编译模式: 目标架构 $TARGET_ARCH"

    # 检查交叉编译所需的 OpenSSL 开发头文件
    local cross_ssl_dir=""
    case "$TARGET_ARCH" in
      aarch64) cross_ssl_dir="/usr/include/aarch64-linux-gnu/openssl" ;;
      x86_64)  cross_ssl_dir="/usr/include/x86_64-linux-gnu/openssl" ;;
    esac
    if [ -n "$cross_ssl_dir" ] && [ ! -d "$cross_ssl_dir" ]; then
      echo "错误: 缺少目标架构 (${TARGET_ARCH}) 的 OpenSSL 开发头文件"
      echo "  Fast-DDS 依赖 libssl-dev:arm64 提供 opensslconf.h"
      echo ""
      echo "修复:"
      echo "  sudo dpkg --add-architecture arm64"
      echo "  sudo apt update"
      echo "  sudo apt install libssl-dev:arm64"
      echo ""
      echo "提示: 推荐使用 Docker 编译以避免交叉依赖问题:"
      echo "  ./scripts/docker_build.sh $DISTRO"
      exit 1
    fi
  fi

  # 按开关组装编译目标
  if [ "$ENABLE_VISION" = true ]; then
    TARGET_PKGS+=("${VISION_PKGS[@]}")
  fi
  if [ "$ENABLE_CLI" = true ]; then
    TARGET_PKGS+=("${CLI_PKGS[@]}")
  fi

  # Python 版本兼容性检测 (仅 CLI 需要)
  if [ "$ENABLE_CLI" = true ]; then
    local py_major py_minor
    py_major=$(python3 -c 'import sys; print(sys.version_info.major)')
    py_minor=$(python3 -c 'import sys; print(sys.version_info.minor)')
    if [ "$DISTRO" = "humble" ] && [ "$((py_major * 100 + py_minor))" -ge 312 ]; then
      echo "[ERROR] Python ${py_major}.${py_minor} 与 ${DISTRO} 的 pybind11 不兼容, 无法编译 CLI 模块"
      echo "        请使用 Python 3.10/3.11 环境 (Ubuntu 22.04)"
      echo "        如仅需 core + vision, 请在脚本顶部设置 ENABLE_CLI=false 后重新编译"
      exit 1
    fi
  fi

  # Cross-compile: remove packages that are COLCON_IGNORE'd
  # (currently none — rclpy and rosidl_generator_py are enabled with libpython3-dev:arm64)

  # 关键包预检 (用 colcon 索引，避免误匹配依赖名)
  if ! command -v colcon &>/dev/null; then
    echo "错误: 未找到 colcon — pip3 install colcon-common-extensions"
    exit 1
  fi
  local missing=() colcon_pkgs pkg
  colcon_pkgs="$(cd "$SRC_DIR" && colcon list --names-only 2>/dev/null | sort -u)"
  for pkg in "${TARGET_PKGS[@]}"; do
    if ! echo "$colcon_pkgs" | grep -qx "$pkg"; then
      missing+=("$pkg")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "错误: workspace 中缺少 colcon 包: ${missing[*]}"
    echo "修复: ./scripts/update_src.sh $DISTRO"
    if [ "$ENABLE_CLI" = true ]; then
      echo "      (CLI 包由 repos/${DISTRO}-cli.repos 提供，update_src.sh 会自动导入)"
    fi
    exit 1
  fi

  # Vision 模块系统依赖预检 (skip for cross-compile, handled in Docker)
  # NOTE: OpenCV 由 thirdparty 提供，不再依赖系统 libopencv-dev
  if [ "$ENABLE_VISION" = true ] && [ "$TARGET_ARCH" = "$(uname -m)" ]; then
    local missing_sys=()
    dpkg -s libboost-dev &>/dev/null || missing_sys+=("libboost-dev (cv_bridge 需要 Boost)")
    if [ "${#missing_sys[@]}" -gt 0 ]; then
      echo "错误: vision 模块缺少系统依赖:"
      printf '  %s\n' "${missing_sys[@]}"
      echo "安装: sudo apt install -y libboost-dev"
      echo "提示: 如不需要 vision, 请在脚本顶部设置 ENABLE_VISION=false"
      exit 1
    fi
  fi

  # Python / vendor 预检 (skip for cross-compile)
  if [ "$TARGET_ARCH" = "$(uname -m)" ]; then
    local missing_py=()
    python3 -c "import lark" 2>/dev/null || missing_py+=("python3-lark (rosidl_parser 需要, core 依赖)")
    if [ "${#missing_py[@]}" -gt 0 ]; then
      echo "错误: 缺少 Python 模块:"
      printf '  %s\n' "${missing_py[@]}"
      echo "安装: sudo apt install -y ${missing_py[*]}"
      exit 1
    fi
    if [ "$ENABLE_CLI" = true ] && [ ! -f "$SRC_DIR/ros2/pybind11_vendor/pybind11_src/CMakeLists.txt" ]; then
      echo "错误: 缺少 vendored pybind11 源码 (rclpy/CLI 需要)"
      echo "修复: ./scripts/update_src.sh $DISTRO   # 会同步 *-cli.repos 中的 pybind11_src"
      exit 1
    fi
  fi

}

# 清除 vendor 路径重命名后残留的 CMake 缓存
purge_stale_vendor_builds() {
  local build_base=$1
  local foonathan_build="$build_base/foonathan_memory_vendor"
  if [ -d "$foonathan_build" ] \
    && grep -rq 'foo_mem_src' "$foonathan_build" 2>/dev/null \
    && [ -d "$SRC_DIR/eProsima/foonathan_memory_vendor/foonathan_memory_src" ]; then
    echo "[INFO] 清除 foonathan_memory_vendor 旧缓存 (foo_mem_src → foonathan_memory_src)"
    rm -rf "$foonathan_build"
  fi
}

clean_env() {
  for var in AMENT_PREFIX_PATH CMAKE_PREFIX_PATH COLCON_PREFIX_PATH \
    PYTHONPATH LD_LIBRARY_PATH ROS_PACKAGE_PATH ROS_VERSION \
    ROS_DISTRO ROS_PYTHON_VERSION; do
    unset "$var" 2>/dev/null || true
  done
  export PATH="$(echo "$PATH" | tr ':' '\n' | grep -v '/opt/ros' | paste -sd:)"
}

mark_ignore_pkgs() {
  for pkg in "${SKIP_PKGS[@]}"; do
    find "$SRC_DIR" -path "*/${pkg}/package.xml" \
      -exec sh -c 'touch "$(dirname "$1")/COLCON_IGNORE"' _ {} \; 2>/dev/null
  done
}

do_build() {
  local arch_dir="$OUTPUT_DIR/${TARGET_ARCH}"
  local build_base="$arch_dir/build"
  local install_base="$arch_dir/colcon_install"
  local log_base="$arch_dir/log"

  if [ "$CLEAN_BUILD" = true ]; then
    echo "[INFO] 清除编译缓存 (clean build)..."
    rm -rf "$build_base" "$install_base" "$log_base"
  else
    purge_stale_vendor_builds "$build_base"
  fi

  local features=""
  [ "$ENABLE_VISION" = true ] && features+="vision "
  [ "$ENABLE_CLI" = true ] && features+="cli"
  echo "[INFO] colcon build (${#TARGET_PKGS[@]} packages, ${features:-core}, arch: $TARGET_ARCH)..."

  local asio_include="$SRC_DIR/chriskohlhoff/asio/asio/include"
  local tinyxml2_dir="$SRC_DIR/ros2/tinyxml2_vendor/tinyxml2_src"

  # OpenCV: 从 thirdparty 获取 (自动解析路径)
  local opencv_dir="${OPENCV_DIR:-$REPO_ROOT/../thirdparty/output/$TARGET_ARCH/opencv}"
  if [ ! -d "$opencv_dir" ]; then
    echo "[ERROR] OpenCV not found at $opencv_dir"
    echo "[HINT] Build thirdparty first: cd ../thirdparty && ./build.sh -t $TARGET_ARCH opencv"
    exit 1
  fi
  echo "[INFO] Using OpenCV from: $opencv_dir"

  # Common cmake args (shared between x86 and arm64)
  local cmake_args=(
    -DCMAKE_BUILD_TYPE=Release
    -DBUILD_TESTING=OFF
    -DTRACETOOLS_DISABLED=ON
    -DFORCE_BUILD_VENDOR_PKG=ON
    -DCMAKE_INCLUDE_PATH="$asio_include"
    -DTINYXML2_FROM_SOURCE=ON
    -DTINYXML2_INCLUDE_DIR="$tinyxml2_dir"
    -DTINYXML2_SOURCE_DIR="$tinyxml2_dir"
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DOpenCV_DIR="$opencv_dir/lib/cmake/opencv4"
  )

  # Patch cv_bridge to skip Python bindings (we only need C++ lib)
  local cv_bridge_dir
  cv_bridge_dir=$(find "$SRC_DIR" -path "*/cv_bridge/CMakeLists.txt" -exec dirname {} \; | head -1)
  if [ -n "$cv_bridge_dir" ]; then
    find "$cv_bridge_dir" -name "CMakeLists.txt" -exec \
      sed -i -E 's/if\(ANDROID[^)]*\)/if(TRUE)/g; s/if\(NOT ANDROID[^)]*\)/if(FALSE)/g' {} \;
    echo "[INFO] Patched cv_bridge to skip Python bindings"
  fi

  # Cross-compile: add toolchain
  if [ "$TARGET_ARCH" != "$(uname -m)" ]; then
    local toolchain="$REPO_ROOT/toolchain/aarch64-linux-gnu.cmake"
    if [ ! -f "$toolchain" ]; then
      toolchain="/opt/toolchain/aarch64-linux-gnu.cmake"
    fi
    cmake_args+=(-DCMAKE_TOOLCHAIN_FILE="$toolchain")
    # Pre-fill TRY_RUN results (can't execute target binaries on host)
    # Fast-DDS shared_mutex priority check: works on Linux aarch64
    cmake_args+=(-DSM_RUN_RESULT=0 -DSM_RUN_RESULT__TRYRUN_OUTPUT="PTHREAD_RWLOCK_PREFER_READER_NP")
    cmake_args+=(-DSM_RUN_OUTPUT="PTHREAD_RWLOCK_PREFER_READER_NP")
    # merge-install puts all libs under one dir; single rpath-link suffices
    cmake_args+=("-DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath-link,$install_base/lib")
    cmake_args+=("-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-rpath-link,$install_base/lib")
    echo "[INFO] 使用交叉编译 toolchain: $toolchain"
  fi

  local merge_install_arg=()
  if [ "$TARGET_ARCH" != "$(uname -m)" ]; then
    merge_install_arg=(--merge-install)
  fi

  colcon --log-base "$log_base" build \
    --build-base "$build_base" \
    --install-base "$install_base" \
    "${merge_install_arg[@]}" \
    --cmake-args "${cmake_args[@]}" \
    --no-warn-unused-cli \
    --packages-up-to "${TARGET_PKGS[@]}"

  echo "[INFO] 打包 $TARBALL..."
  mkdir -p "$arch_dir"
  tar czf "$arch_dir/$TARBALL" -C "$install_base" .

  local size
  size="$(du -sh "$arch_dir/$TARBALL" | cut -f1)"
  echo "[OK] 产物: $arch_dir/$TARBALL ($size)"
}

# ─── 主流程 ───

parse_args "$@"
preflight_check

TARBALL="ros2-${DISTRO}-${TARGET_ARCH}.tar.gz"

echo "=========================================="
echo " 编译 ROS2 ${DISTRO^^} (${TARGET_ARCH})"
echo "=========================================="

START_TIME=$(date +%s)

clean_env
cd "$SRC_DIR"
mark_ignore_pkgs
do_build

ELAPSED=$(($(date +%s) - START_TIME))
printf "[OK] 总耗时: %d分%d秒\n" $((ELAPSED / 60)) $((ELAPSED % 60))
