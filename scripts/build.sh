#!/usr/bin/env bash
# build.sh — 从源码编译 ROS2 核心并打包为自包含 tarball
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<'EOF'
用法: ./scripts/build.sh <distro> [选项]

从源码编译 ROS2 核心并打包为自包含 tarball。

参数:
  distro                 humble 或 jazzy

选项:
  -o, --output DIR       输出目录 (默认: <repo>/dist)
  -c, --copy-to PATH     部署到指定项目 (默认: ~/buddy_robot)
  -h, --help             显示帮助

示例:
  ./scripts/build.sh jazzy
  ./scripts/build.sh jazzy -o /tmp
  ./scripts/build.sh jazzy -c ~/buddy_robot
EOF
}

# ─── 默认值 ───
DEFAULT_OUTPUT_DIR="$REPO_ROOT/dist"
DEFAULT_COPY_TO="$HOME/buddy_robot"

# ─── 解析参数 ───
DISTRO=""
OUTPUT_DIR=""
COPY_TO=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -o|--output)
            OUTPUT_DIR="${2:?缺少输出目录}"
            shift 2
            ;;
        -c|--copy-to)
            COPY_TO="${2:?缺少目标路径}"
            shift 2
            ;;
        humble|jazzy)
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

# 应用默认值
OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
if [ -z "$COPY_TO" ] && [ -d "$DEFAULT_COPY_TO" ]; then
    COPY_TO="$DEFAULT_COPY_TO"
fi

SRC_DIR="$REPO_ROOT/src/$DISTRO"
if [ ! -d "$SRC_DIR" ]; then
    echo "错误: 源码目录不存在: $SRC_DIR"
    echo "请先运行: ./scripts/update_src.sh $DISTRO"
    exit 1
fi

PKG_COUNT="$(find "$SRC_DIR" -name "package.xml" | wc -l)"
if [ "$PKG_COUNT" -lt 10 ]; then
    echo "错误: 源码不完整，只找到 $PKG_COUNT 个包（预期 80+）"
    echo "请重新拉取: rm -rf src/$DISTRO && ./scripts/update_src.sh $DISTRO"
    exit 1
fi

ARCH="$(uname -m)"
TARBALL="ros2-${DISTRO}-${ARCH}.tar.gz"

echo "=========================================="
echo " 编译 ROS2 ${DISTRO^^} (${ARCH})"
echo "=========================================="

# ─── 清理环境，确保纯源码编译 ───
# 清除所有 ROS 相关环境变量，防止 /opt/ros 干扰
for var in AMENT_PREFIX_PATH CMAKE_PREFIX_PATH COLCON_PREFIX_PATH \
           PYTHONPATH LD_LIBRARY_PATH ROS_PACKAGE_PATH ROS_VERSION \
           ROS_DISTRO ROS_PYTHON_VERSION; do
    unset "$var" 2>/dev/null || true
done
# 从 PATH 中移除 /opt/ros 路径
export PATH="$(echo "$PATH" | tr ':' '\n' | grep -v '/opt/ros' | paste -sd:)"

cd "$SRC_DIR"
rm -rf build install log

# ─── 编译 ───
echo "[INFO] colcon build..."
colcon build \
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    --packages-up-to \
        rclcpp_components rclcpp_lifecycle \
        std_msgs sensor_msgs builtin_interfaces \
        rosidl_default_generators

# ─── 打包 ───
echo "[INFO] 打包 $TARBALL..."
mkdir -p "$OUTPUT_DIR"
tar czf "$OUTPUT_DIR/$TARBALL" -C install .

SIZE="$(du -sh "$OUTPUT_DIR/$TARBALL" | cut -f1)"
echo "[OK] 产物: $OUTPUT_DIR/$TARBALL ($SIZE)"

# ─── 部署到 buddy_robot ───
if [ -n "$COPY_TO" ]; then
    INSTALL_DIR="$COPY_TO/third_party/ros2/$DISTRO/install"
    echo "[INFO] 部署到 $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    tar xzf "$OUTPUT_DIR/$TARBALL" -C "$INSTALL_DIR"
    echo "[OK] 已部署到 $INSTALL_DIR"
    echo ""
    echo "后续步骤:"
    echo "  cd $COPY_TO"
    echo "  bash scripts/build_all.sh build"
    echo "  bash scripts/build_all.sh test"
fi
