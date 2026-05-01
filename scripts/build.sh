#!/usr/bin/env bash
# build.sh — 从源码编译 ROS2 核心并打包为自包含 tarball
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── 要编译的目标包 ───
TARGET_PKGS=(
  rclcpp_components rclcpp_lifecycle
  std_msgs sensor_msgs builtin_interfaces
  rosidl_default_generators
  yaml_cpp_vendor
)

# ─── 要跳过的测试包 ───
SKIP_PKGS=(test_msgs test_interface_files)

# ─── 函数定义 ───

usage() {
  cat <<'EOF'
用法: ./scripts/build.sh <distro> [选项]

从源码编译 ROS2 核心并打包为自包含 tarball。

参数:
  distro                 humble 或 jazzy

选项:
  -o, --output DIR       输出目录 (默认: <repo>/output/<distro>)
  -c, --clean            清除编译缓存，全量重新编译
  -h, --help             显示帮助

示例:
  ./scripts/build.sh jazzy
  ./scripts/build.sh jazzy -o /tmp
  ./scripts/build.sh jazzy -c            # 全量重新编译
EOF
}

parse_args() {
  DISTRO=""
  OUTPUT_DIR=""
  CLEAN_BUILD=false

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

  OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output/$DISTRO}"
  SRC_DIR="$REPO_ROOT/src/$DISTRO"
}

preflight_check() {
  if [ ! -d "$SRC_DIR" ]; then
    echo "错误: 源码目录不存在: $SRC_DIR"
    echo "请先运行: ./scripts/update_src.sh $DISTRO"
    exit 1
  fi

  # 关键包预检
  local missing=()
  for pkg in "${TARGET_PKGS[@]}"; do
    if ! grep -Rqs --include "package.xml" "<name>${pkg}</name>" "$SRC_DIR"; then
      missing+=("$pkg")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "错误: 源码缺少关键包: ${missing[*]}"
    echo "修复: rm -rf src/$DISTRO && ./scripts/update_src.sh $DISTRO"
    exit 1
  fi

  # 系统库预检
  local SYS_DEPS=()
  local missing_sys=()
  for dep in "${SYS_DEPS[@]}"; do
    dpkg -s "$dep" &>/dev/null || missing_sys+=("$dep")
  done
  if [ "${#missing_sys[@]}" -gt 0 ]; then
    echo "错误: 缺少系统依赖:"
    printf '  %s\n' "${missing_sys[@]}"
    echo "安装: sudo apt install -y ${missing_sys[*]}"
    exit 1
  fi

  # Python 模块预检（仅检查实际编译中确认必须的）
  local missing_py=()
  python3 -c "import lark" 2>/dev/null || missing_py+=("python3-lark")
  if [ "${#missing_py[@]}" -gt 0 ]; then
    echo "错误: 缺少 Python 模块:"
    printf '  %s\n' "${missing_py[@]}"
    echo "安装: sudo apt install -y ${missing_py[*]}"
    exit 1
  fi

  # 工具链预检
  if ! command -v colcon &>/dev/null; then
    echo "错误: 未找到 colcon — pip3 insgall colcon-common-extensions"
    exit 1
  fi
}

clean_env() {
  # 清除 ROS 相关环境变量，防止 /opt/ros 干扰
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
  local build_base="$OUTPUT_DIR/build"
  local install_base="$OUTPUT_DIR/colcon_install"
  local log_base="$OUTPUT_DIR/log"

  if [ "$CLEAN_BUILD" = true ]; then
    echo "[INFO] 清除编译缓存 (clean build)..."
    rm -rf "$build_base" "$install_base" "$log_base"
  fi

  echo "[INFO] colcon build..."
  local asio_include="$SRC_DIR/chriskohlhoff/asio/asio/include"
  local tinyxml2_dir="$SRC_DIR/leethomason/tinyxml2"
  colcon --log-base "$log_base" build \
    --build-base "$build_base" \
    --install-base "$install_base" \
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    -DTRACETOOLS_DISABLED=ON -DFORCE_BUILD_VENDOR_PKG=ON \
    -DCMAKE_INCLUDE_PATH="$asio_include" \
    -DTINYXML2_FROM_SOURCE=ON \
    -DTINYXML2_INCLUDE_DIR="$tinyxml2_dir" \
    -DTINYXML2_SOURCE_DIR="$tinyxml2_dir" \
    --no-warn-unused-cli \
    --packages-up-to "${TARGET_PKGS[@]}"

  echo "[INFO] 打包 $TARBALL..."
  mkdir -p "$OUTPUT_DIR"
  tar czf "$OUTPUT_DIR/$TARBALL" -C "$install_base" .

  local size
  size="$(du -sh "$OUTPUT_DIR/$TARBALL" | cut -f1)"
  echo "[OK] 产物: $OUTPUT_DIR/$TARBALL ($size)"
}

# ─── 主流程 ───

parse_args "$@"
preflight_check

ARCH="$(uname -m)"
TARBALL="ros2-${DISTRO}-${ARCH}.tar.gz"

echo "=========================================="
echo " 编译 ROS2 ${DISTRO^^} (${ARCH})"
echo "=========================================="

START_TIME=$(date +%s)

clean_env
cd "$SRC_DIR"
mark_ignore_pkgs
do_build

ELAPSED=$(($(date +%s) - START_TIME))
printf "[OK] 总耗时: %d分%d秒\n" $((ELAPSED / 60)) $((ELAPSED % 60))
