#!/usr/bin/env bash
# docker_build.sh — 在干净 Docker 容器中编译 ROS2 核心
# 自动缓存 base 镜像 (apt + pip 依赖)，加速后续编译
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── 函数定义 ───

usage() {
    cat <<'EOF'
用法: ./scripts/docker_build.sh <distro> [选项]

在干净 Ubuntu 容器中编译 ROS2 核心，生成自包含 tarball。
前提: 需要 Docker 已安装并可运行。

参数:
  distro                 humble 或 jazzy

选项:
  -o, --output DIR       输出目录 (默认: <repo>/output/<distro>)
  -c, --copy-to PATH     部署到指定路径 (默认: <repo>/output/<distro>/install)
  --no-cache             强制重建 base 镜像
  -h, --help             显示帮助

示例:
  ./scripts/docker_build.sh jazzy
  ./scripts/docker_build.sh humble -o /tmp
  ./scripts/docker_build.sh jazzy -c ~/buddy_robot
EOF
}

parse_args() {
    DISTRO=""
    OUTPUT_DIR=""
    COPY_TO=""
    NO_CACHE=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -o|--output) OUTPUT_DIR="${2:?缺少输出目录}"; shift 2 ;;
            -c|--copy-to) COPY_TO="${2:?缺少目标路径}"; shift 2 ;;
            --no-cache) NO_CACHE="--no-cache"; shift ;;
            humble|jazzy) DISTRO="$1"; shift ;;
            *) echo "未知参数: $1"; usage; exit 1 ;;
        esac
    done

    if [ -z "$DISTRO" ]; then
        echo "错误: 必须指定 distro (humble 或 jazzy)"
        usage
        exit 1
    fi

    OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output/$DISTRO}"
    COPY_TO="${COPY_TO:-$OUTPUT_DIR/install}"
    SRC_DIR="$REPO_ROOT/src/$DISTRO"
}

preflight_check() {
    if [ ! -d "$SRC_DIR" ]; then
        echo "错误: 源码目录不存在: $SRC_DIR"
        echo "请先运行: ./scripts/update_src.sh $DISTRO"
        exit 1
    fi
    if ! command -v docker &>/dev/null; then
        echo "错误: Docker 未安装 — https://docs.docker.com/engine/install/"
        exit 1
    fi
    if ! docker info &>/dev/null; then
        echo "错误: Docker 服务未启动或当前用户无权限"
        echo "尝试: sudo systemctl start docker && sudo usermod -aG docker \$USER"
        exit 1
    fi
}

build_base_image() {
    local base_image="ros2-core-build:${DISTRO}-base"
    if docker image inspect "$base_image" &>/dev/null && [ -z "$NO_CACHE" ]; then
        echo "[OK] 复用缓存 base 镜像: $base_image"
    else
        echo "[INFO] 构建 base 镜像: $base_image ..."
        docker build $NO_CACHE \
            --target "base-${DISTRO}" \
            -t "$base_image" \
            -f "$REPO_ROOT/Dockerfile" \
            "$REPO_ROOT"
        echo "[OK] base 镜像已缓存: $base_image"
    fi
}

do_build() {
    echo "[INFO] docker build (编译)..."
    docker build \
        --target "export-${DISTRO}" \
        -o "type=local,dest=$OUTPUT_DIR" \
        -f "$REPO_ROOT/Dockerfile" \
        "$REPO_ROOT"

    if [ ! -f "$OUTPUT_DIR/$TARBALL" ]; then
        echo "错误: 编译产物未生成: $OUTPUT_DIR/$TARBALL"
        exit 1
    fi

    local size
    size="$(du -sh "$OUTPUT_DIR/$TARBALL" | cut -f1)"
    echo "[OK] 产物: $OUTPUT_DIR/$TARBALL ($size)"
}

deploy() {
    [ -n "$COPY_TO" ] || return 0
    echo "[INFO] 部署到 $COPY_TO"
    rm -rf "$COPY_TO"
    mkdir -p "$COPY_TO"
    tar xzf "$OUTPUT_DIR/$TARBALL" -C "$COPY_TO"
    echo "[OK] 已部署到 $COPY_TO"
}

# ─── 主流程 ───

parse_args "$@"
preflight_check

ARCH="$(uname -m)"
TARBALL="ros2-${DISTRO}-${ARCH}.tar.gz"

echo "=========================================="
echo " Docker 编译 ROS2 ${DISTRO^^} (${ARCH})"
echo "=========================================="

mkdir -p "$OUTPUT_DIR"
build_base_image
do_build
deploy
