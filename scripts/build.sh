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
  -c, --copy-to PATH     部署到指定路径 (默认: <repo>/output/<distro>/install)
  -h, --help             显示帮助

示例:
  ./scripts/build.sh jazzy
  ./scripts/build.sh jazzy -o /tmp
  ./scripts/build.sh jazzy -c ~/buddy_robot
EOF
}

parse_args() {
    DISTRO=""
    OUTPUT_DIR=""
    COPY_TO=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -o|--output) OUTPUT_DIR="${2:?缺少输出目录}"; shift 2 ;;
            -c|--copy-to) COPY_TO="${2:?缺少目标路径}"; shift 2 ;;
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

    # 系统库预检（仅检查实际编译中确认必须的库）
    local SYS_DEPS=(
        libtinyxml2-dev libasio-dev
    )
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
        echo "错误: 未找到 colcon — pip3 install colcon-common-extensions"
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
    rm -rf "$build_base" "$install_base" "$log_base"

    echo "[INFO] colcon build..."
    colcon --log-base "$log_base" build \
        --build-base "$build_base" \
        --install-base "$install_base" \
        --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
                     -DTRACETOOLS_DISABLED=ON --no-warn-unused-cli \
        --packages-up-to "${TARGET_PKGS[@]}"

    echo "[INFO] 打包 $TARBALL..."
    mkdir -p "$OUTPUT_DIR"
    tar czf "$OUTPUT_DIR/$TARBALL" -C "$install_base" .

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
echo " 编译 ROS2 ${DISTRO^^} (${ARCH})"
echo "=========================================="

clean_env
cd "$SRC_DIR"
mark_ignore_pkgs
do_build
deploy
