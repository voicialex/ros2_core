#!/usr/bin/env bash
# docker_build.sh — 在 Docker 容器中编译 ROS2 核心 (x86 native / arm64 cross)
# 新环境只需 Docker 即可编译两种架构
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── 函数定义 ───

usage() {
    cat <<'EOF'
用法: ./scripts/docker_build.sh <distro> [选项]

在 Docker 容器中编译 ROS2 核心，生成自包含 tarball。
x86_64: 容器内 native 编译
aarch64: 容器内交叉编译 (无需 ARM 硬件)

参数:
  distro                 humble 或 jazzy

选项:
  -t ARCH                目标架构: x86_64 (默认) 或 arm64/aarch64
  -o, --output DIR       输出目录 (默认: <repo>/output/<distro>)
  -c, --clean            清除 colcon 编译缓存后全量重编 (传给 build.sh)
  --no-cache             强制重建 base 镜像
  -h, --help             显示帮助

示例:
  ./scripts/docker_build.sh humble            # x86_64 native in Docker
  ./scripts/docker_build.sh humble -t arm64   # arm64 cross-compile in Docker
  ./scripts/docker_build.sh humble --no-cache
EOF
}

parse_args() {
    DISTRO=""
    OUTPUT_DIR=""
    NO_CACHE=""
    CLEAN_BUILD=false
    TARGET_ARCH="x86_64"

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -o|--output) OUTPUT_DIR="${2:?缺少输出目录}"; shift 2 ;;
            -c|--clean) CLEAN_BUILD=true; shift ;;
            --no-cache) NO_CACHE="--no-cache"; shift ;;
            -t) TARGET_ARCH="${2:?缺少架构}"; shift 2 ;;
            humble|jazzy) DISTRO="$1"; shift ;;
            *) echo "未知参数: $1"; usage; exit 1 ;;
        esac
    done

    if [ -z "$DISTRO" ]; then
        echo "错误: 必须指定 distro (humble 或 jazzy)"
        usage
        exit 1
    fi

    # Normalize arch
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

# 每个 distro 只有一个统一镜像 (x86 native + arm64 cross)
get_docker_target() {
    echo "$DISTRO"
}

get_image_name() {
    echo "ros2-core/${DISTRO}:dev"
}

build_base_image() {
    local target
    target="$(get_docker_target)"
    local base_image
    base_image="$(get_image_name)"

    if docker image inspect "$base_image" &>/dev/null && [ -z "$NO_CACHE" ]; then
        echo "[OK] 复用缓存 base 镜像: $base_image"
    else
        echo "[INFO] 构建 base 镜像: $base_image ..."
        docker build $NO_CACHE \
            --target "$target" \
            -t "$base_image" \
            -f "$REPO_ROOT/Dockerfile" \
            "$REPO_ROOT"
        echo "[OK] base 镜像已缓存: $base_image"
    fi
}

do_build() {
    local base_image
    base_image="$(get_image_name)"

    local clean_arg=()
    [ "$CLEAN_BUILD" = true ] && clean_arg=(-c)
    echo "[INFO] Docker 编译 (arch: $TARGET_ARCH${clean_arg:+, clean build})..."

    # Prepare prebuilt directory in ros2_core
    local prebuilt_dir="$REPO_ROOT/prebuilt/$TARGET_ARCH/opencv"
    mkdir -p "$prebuilt_dir"

    # Copy from thirdparty if not already in prebuilt
    local thirdparty_opencv="$REPO_ROOT/../thirdparty/output/$TARGET_ARCH/opencv"
    if [ ! -d "$thirdparty_opencv" ]; then
        echo "[ERROR] OpenCV not found at $thirdparty_opencv"
        echo "[HINT] Build thirdparty first: cd ../thirdparty && ./build.sh -t $TARGET_ARCH opencv"
        exit 1
    fi

    # Sync from thirdparty to prebuilt if missing or newer
    if [ ! -f "$prebuilt_dir/lib/libopencv_core.so" ] || \
       [ "$thirdparty_opencv/lib/libopencv_core.so" -nt "$prebuilt_dir/lib/libopencv_core.so" ]; then
        echo "[INFO] Copying OpenCV to prebuilt/$TARGET_ARCH/opencv"
        rm -rf "$prebuilt_dir"
        cp -a "$thirdparty_opencv" "$prebuilt_dir"
    else
        echo "[INFO] Using cached OpenCV from prebuilt/$TARGET_ARCH/opencv"
    fi

    # Prepare libcurl in prebuilt directory
    local prebuilt_libcurl="$REPO_ROOT/prebuilt/$TARGET_ARCH/libcurl"
    mkdir -p "$prebuilt_libcurl"

    local thirdparty_libcurl="$REPO_ROOT/../thirdparty/output/$TARGET_ARCH/libcurl"
    if [ ! -d "$thirdparty_libcurl" ]; then
        echo "[ERROR] libcurl not found at $thirdparty_libcurl"
        echo "[HINT] Build thirdparty first: cd ../thirdparty && ./build.sh -t $TARGET_ARCH libcurl"
        exit 1
    fi

    # Sync from thirdparty to prebuilt if missing or newer
    if [ ! -f "$prebuilt_libcurl/lib/libcurl.so" ] || \
       [ "$thirdparty_libcurl/lib/libcurl.so" -nt "$prebuilt_libcurl/lib/libcurl.so" ]; then
        echo "[INFO] Copying libcurl to prebuilt/$TARGET_ARCH/libcurl"
        rm -rf "$prebuilt_libcurl"
        cp -a "$thirdparty_libcurl" "$prebuilt_libcurl"
    else
        echo "[INFO] Using cached libcurl from prebuilt/$TARGET_ARCH/libcurl"
    fi

    docker run --rm \
        --network host \
        -e http_proxy="${http_proxy:-}" \
        -e https_proxy="${https_proxy:-}" \
        -e no_proxy="${no_proxy:-}" \
        -e OPENCV_DIR=/opt/opencv \
        -e CURL_DIR=/opt/libcurl \
        -u "$(id -u):$(id -g)" \
        -v "$REPO_ROOT:/ws" \
        -v "$prebuilt_dir:/opt/opencv:ro" \
        -v "$prebuilt_libcurl:/opt/libcurl:ro" \
        "$base_image" \
        bash /ws/scripts/build.sh "$DISTRO" --arch "$TARGET_ARCH" \
            "${clean_arg[@]}" -o "/ws/output/$DISTRO"

    local arch_output="$OUTPUT_DIR/$TARGET_ARCH"
    if [ ! -f "$arch_output/$TARBALL" ]; then
        echo "错误: 编译产物未生成: $arch_output/$TARBALL"
        exit 1
    fi

    local size
    size="$(du -sh "$arch_output/$TARBALL" | cut -f1)"
    echo "[OK] 产物: $arch_output/$TARBALL ($size)"
}

# ─── 主流程 ───

parse_args "$@"
preflight_check

TARBALL="ros2-${DISTRO}-${TARGET_ARCH}.tar.gz"

echo "=========================================="
echo " Docker 编译 ROS2 ${DISTRO^^} (${TARGET_ARCH})"
echo "=========================================="

START_TIME=$(date +%s)

mkdir -p "$OUTPUT_DIR"
build_base_image
do_build

ELAPSED=$(( $(date +%s) - START_TIME ))
printf "[OK] 总耗时: %d分%d秒\n" $((ELAPSED/60)) $((ELAPSED%60))
