#!/usr/bin/env bash
# docker_build.sh — 在干净 Docker 容器中编译 ROS2 核心
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<'EOF'
用法: ./scripts/docker_build.sh <distro> [选项]

在干净 Ubuntu 容器中编译 ROS2 核心，生成自包含 tarball。
无需本机安装 ROS2 或编译工具。

前提: 需要 Docker 已安装并可运行。

参数:
  distro                 humble 或 jazzy

选项:
  -o, --output DIR       输出目录 (默认: <repo>/dist)
  -c, --copy-to PATH     部署到指定项目 (默认: ~/buddy_robot)
  -h, --help             显示帮助

示例:
  ./scripts/docker_build.sh jazzy
  ./scripts/docker_build.sh humble -o /tmp
  ./scripts/docker_build.sh jazzy -c ~/buddy_robot
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

# 检查 Docker
if ! command -v docker &>/dev/null; then
    echo "错误: Docker 未安装"
    echo "安装: https://docs.docker.com/engine/install/"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "错误: Docker 服务未启动或当前用户无权限"
    echo "尝试: sudo systemctl start docker && sudo usermod -aG docker \$USER"
    exit 1
fi

ARCH="$(uname -m)"
TARBALL="ros2-${DISTRO}-${ARCH}.tar.gz"

echo "=========================================="
echo " Docker 编译 ROS2 ${DISTRO^^} (${ARCH})"
echo "=========================================="

mkdir -p "$OUTPUT_DIR"

# ─── Docker 编译 ───
echo "[INFO] docker build..."
docker build \
    --build-arg DISTRO="$DISTRO" \
    --target "export-${DISTRO}" \
    -o "type=local,dest=$OUTPUT_DIR" \
    -f "$REPO_ROOT/Dockerfile" \
    "$REPO_ROOT"

if [ ! -f "$OUTPUT_DIR/$TARBALL" ]; then
    echo "错误: 编译产物未生成: $OUTPUT_DIR/$TARBALL"
    exit 1
fi

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
