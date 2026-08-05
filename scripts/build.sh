#!/usr/bin/env bash
# build.sh — 编译 ROS2 核心并打包为自包含 tarball
# 默认走 Docker（推荐），加 --native 在宿主机直接编译。
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
用法: ./scripts/build.sh [distro] [选项]

从源码编译 ROS2 核心并打包为自包含 tarball。默认使用 Docker 编译 humble x86_64。

参数:
  distro                 目标发行版: humble (默认) 或 jazzy

选项:
  -t, --arch ARCH        目标架构: x86_64 (默认) 或 arm64/aarch64
  -o, --output DIR       输出目录 (默认: <repo>/output/<distro>)
  -c, --clean            清除 colcon 编译缓存，全量重编
  --no-cache             强制重建 Docker base 镜像（仅 Docker 模式）
  --native               在宿主机直接编译（跳过 Docker）
  --all                  全编译: humble/jazzy × x86_64/aarch64 (用于发版)
  -h, --help             显示帮助

示例:
  ./scripts/build.sh                        # Docker 编译 humble x86_64
  ./scripts/build.sh -t arm64               # Docker 交叉编译 humble aarch64
  ./scripts/build.sh jazzy --native         # 宿主机编译 jazzy x86_64
  ./scripts/build.sh --all                  # 全编译 4 个 tarball
  ./scripts/build.sh --all --no-cache       # 重建镜像后全编译
EOF
}

parse_args() {
  DISTRO="humble"
  OUTPUT_DIR=""
  CLEAN_BUILD=false
  TARGET_ARCH="$(uname -m)"
  BUILD_MODE="docker"
  NO_CACHE=""
  BUILD_ALL=false

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -o|--output) OUTPUT_DIR="${2:?缺少输出目录}"; shift 2 ;;
      -c|--clean) CLEAN_BUILD=true; shift ;;
      --no-cache) NO_CACHE="--no-cache"; shift ;;
      --native) BUILD_MODE="native"; shift ;;
      --in-docker) BUILD_MODE="in-docker"; shift ;;
      --all) BUILD_ALL=true; shift ;;
      -t|--arch)
        TARGET_ARCH="${2:?缺少架构}"
        shift 2
        ;;
      humble|jazzy) DISTRO="$1"; shift ;;
      *) echo "未知参数: $1"; usage; exit 1 ;;
    esac
  done

  # Normalize arch names
  case "$TARGET_ARCH" in
    arm64|aarch64) TARGET_ARCH="aarch64" ;;
    x86_64|x86|amd64) TARGET_ARCH="x86_64" ;;
    *) echo "错误: 不支持的架构: $TARGET_ARCH"; exit 1 ;;
  esac

  OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output/$DISTRO}"
  SRC_DIR="$REPO_ROOT/src/$DISTRO"
  TARBALL="ros2-${DISTRO}-${TARGET_ARCH}.tar.gz"
}

# ─── native / in-docker 构建流程 ───

preflight_check() {
  if [ ! -d "$SRC_DIR" ]; then
    echo "错误: 源码目录不存在: $SRC_DIR"
    echo "请先运行: ./scripts/update_src.sh $DISTRO"
    exit 1
  fi

  # Cross-compile: check OpenSSL headers for target arch
  if [ "$TARGET_ARCH" != "$(uname -m)" ]; then
    echo "[INFO] 交叉编译模式: 目标架构 $TARGET_ARCH"
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
      echo "  ./scripts/build.sh $DISTRO"
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

  # Vision 模块系统依赖预检
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

purge_stale_vendor_builds() {
  local build_base=$1
  local foonathan_build="$build_base/foonathan_memory_vendor"
  if [ -d "$foonathan_build" ] \
    && grep -rq 'foo_mem_src' "$foonathan_build" 2>/dev/null \
    && [ -d "$SRC_DIR/eProsima/foonathan_memory_vendor/foonathan_memory_src" ]; then
    echo "[INFO] 清除 foonathan_memory_vendor 旧缓存 (foo_mem_src → foonathan_memory_src)"
    rm -rf "$foonathan_build"
  fi

  # Python extension ABI is derived from the target architecture. Reconfigure
  # all packages when a previous aarch64 build cached the host x86_64 suffix.
  # Only check .so filenames, not file contents — CMakeCache and logs legitimately
  # contain x86_64 paths (the host) even in a correct aarch64 cross-build.
  if [ "$TARGET_ARCH" = "aarch64" ] \
    && find "$build_base" -name '*cpython-*-x86_64-linux-gnu.so' -print -quit 2>/dev/null | grep -q .; then
    echo "[INFO] 清除带有宿主 Python ABI 的 aarch64 编译缓存"
    rm -rf "$build_base"
    rm -rf "$OUTPUT_DIR/${TARGET_ARCH}/colcon_install"
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

copy_python_module() {
  local module=$1 dest=$2 path
  path=$(python3 -c "import importlib.util; s = importlib.util.find_spec('$module'); print(s.submodule_search_locations[0] if s and s.submodule_search_locations else (s.origin if s else ''))")
  if [ -z "$path" ] || [ ! -e "$path" ]; then
    echo "[ERROR] Python runtime module not found: $module"
    return 1
  fi
  cp -a "$path" "$dest/"
}

package_python_runtime() {
  local install_base=$1 py_ver=$2 runtime_root="$install_base/python"
  local deb_arch="$TARGET_ARCH"
  case "$deb_arch" in
    x86_64) deb_arch="amd64" ;;
    aarch64) deb_arch="arm64" ;;
  esac
  local deb_dir="/opt/ros2-runtime-debs/$deb_arch"
  local target_multiarch
  case "$TARGET_ARCH" in
    aarch64) target_multiarch="aarch64-linux-gnu" ;;
    x86_64)  target_multiarch="x86_64-linux-gnu" ;;
  esac
  local python_lib_dir="$runtime_root/usr/lib/${target_multiarch}"
  # Ubuntu 24.04 (noble) renamed libpython3.12 to libpython3.12t64 and merged
  # libmpdec3 into the Python runtime package.
  local python_lib_package="libpython${py_ver}"
  [ "$py_ver" = "3.12" ] && python_lib_package="libpython${py_ver}t64"
  local runtime_debs=(
    "python${py_ver}-minimal" "libpython${py_ver}-minimal"
    "libpython${py_ver}-stdlib" "$python_lib_package" "python${py_ver}"
    "python3-numpy" "python3-yaml" "python3-netifaces"
    "libblas3" "liblapack3" "libgfortran5" "libyaml-0-2"
  )
  [ "$py_ver" != "3.12" ] && runtime_debs+=("libmpdec3")
  local package deb found

  [ "$ENABLE_CLI" = true ] || return 0
  if [ ! -d "$deb_dir" ]; then
    echo "[ERROR] Python runtime debs not found: $deb_dir"
    echo "[HINT] Rebuild the Docker base image: ./scripts/build.sh $DISTRO --no-cache"
    exit 1
  fi

  rm -rf "$runtime_root"
  mkdir -p "$runtime_root"
  for package in "${runtime_debs[@]}"; do
    found=false
    for deb in "$deb_dir"/"${package}"_*_"${deb_arch}".deb; do
      [ -f "$deb" ] || continue
      dpkg-deb -x "$deb" "$runtime_root"
      found=true
      break
    done
    if [ "$found" = false ]; then
      echo "[ERROR] Missing ${deb_arch} runtime deb: $package"
      exit 1
    fi
  done

  # These ROS CLI dependencies are installed on the build image, not by colcon.
  local py_site="$runtime_root/usr/lib/python${py_ver}/site-packages"
  mkdir -p "$py_site"
  for package in argcomplete packaging setuptools pkg_resources; do
    copy_python_module "$package" "$py_site"
  done
  cp -a /usr/local/lib/python${py_ver}/dist-packages/argcomplete-*.dist-info "$py_site/" 2>/dev/null || true
  cp -a /usr/local/lib/python${py_ver}/dist-packages/packaging-*.dist-info "$py_site/" 2>/dev/null || true

  # Dynamic libraries from unpacked runtime debs need to be next to ROS libs.
  # Use find + cp to handle subdirectories (e.g. blas/ for libblas.so.3).
  find "$runtime_root/usr/lib/${target_multiarch}" -name '*.so*' -type f \
    -exec cp -a {} "$install_base/lib/" \; 2>/dev/null || true
  find "$runtime_root/usr/lib/${target_multiarch}" -name '*.so*' -type l \
    -exec cp -a {} "$install_base/lib/" \; 2>/dev/null || true

  # OpenCV imgcodecs links libwebp at runtime; ship it from the build image.
  find "/usr/lib/${target_multiarch}" -maxdepth 1 \( -name 'libwebp*' \) \
    -exec cp -a {} "$install_base/lib/" \; 2>/dev/null || true

  # cv_bridge's Python binding links against target Boost.Python.
  if [ "$ENABLE_VISION" = true ]; then
    cp -a /usr/lib/${target_multiarch}/libboost_python*.so.* "$install_base/lib/" 2>/dev/null || true
  fi

  # ros2 CLI and the ament Python packages expect their install path on sys.path.
  # The J6M image links /bin/bash to zsh, so it needs a shell-native setup file.
  cat > "$install_base/ros2-env.sh" <<EOF
# Source this file from a real Bash shell to enable the bundled Python runtime.
_ROS2_PREFIX="\$(builtin cd "\$(dirname "\${BASH_SOURCE[0]}")" > /dev/null && pwd)"
export ROS2_PYTHON_HOME="\$_ROS2_PREFIX/python/usr"
export PYTHONHOME="\$ROS2_PYTHON_HOME"
export LD_LIBRARY_PATH="\$_ROS2_PREFIX/lib:\$ROS2_PYTHON_HOME/lib/${target_multiarch}\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export PYTHONPATH="\$_ROS2_PREFIX/lib/python${py_ver}/site-packages:\$_ROS2_PREFIX/local/lib/python${py_ver}/dist-packages:\$ROS2_PYTHON_HOME/lib/python${py_ver}/site-packages:\$ROS2_PYTHON_HOME/lib/python3/dist-packages\${PYTHONPATH:+:\$PYTHONPATH}"
export PATH="\$_ROS2_PREFIX/bin:\$ROS2_PYTHON_HOME/bin:\$PATH"
export COLCON_PYTHON_EXECUTABLE="\$ROS2_PYTHON_HOME/bin/python${py_ver}"
. "\$_ROS2_PREFIX/setup.bash"
unset _ROS2_PREFIX
EOF
  cat > "$install_base/ros2-env.zsh" <<EOF
# Source this file on J6M, where /bin/bash is linked to zsh.
_ROS2_PREFIX="\$(builtin cd "\$(dirname "\${(%):-%N}")" > /dev/null && pwd)"
export ROS2_PYTHON_HOME="\$_ROS2_PREFIX/python/usr"
export PYTHONHOME="\$ROS2_PYTHON_HOME"
export AMENT_PREFIX_PATH="\$_ROS2_PREFIX\${AMENT_PREFIX_PATH:+:\$AMENT_PREFIX_PATH}"
export CMAKE_PREFIX_PATH="\$_ROS2_PREFIX\${CMAKE_PREFIX_PATH:+:\$CMAKE_PREFIX_PATH}"
export COLCON_PREFIX_PATH="\$_ROS2_PREFIX\${COLCON_PREFIX_PATH:+:\$COLCON_PREFIX_PATH}"
export LD_LIBRARY_PATH="\$_ROS2_PREFIX/lib:\$ROS2_PYTHON_HOME/lib/${target_multiarch}\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export PYTHONPATH="\$_ROS2_PREFIX/lib/python${py_ver}/site-packages:\$_ROS2_PREFIX/local/lib/python${py_ver}/dist-packages:\$ROS2_PYTHON_HOME/lib/python${py_ver}/site-packages:\$ROS2_PYTHON_HOME/lib/python3/dist-packages\${PYTHONPATH:+:\$PYTHONPATH}"
export PATH="\$_ROS2_PREFIX/bin:\$ROS2_PYTHON_HOME/bin:\$PATH"
export COLCON_PYTHON_EXECUTABLE="\$ROS2_PYTHON_HOME/bin/python${py_ver}"
unset _ROS2_PREFIX
EOF
  chmod +x "$install_base/ros2-env.sh" "$install_base/ros2-env.zsh"

  # The generated scripts use /usr/bin/python3. Rewrite only their interpreter
  # line to a relocatable wrapper while leaving normal ROS package code intact.
  mkdir -p "$install_base/bin"
  cat > "$install_base/bin/python3" <<EOF
#!/bin/sh
_ROS2_PREFIX="\$(CDPATH= cd -- "\$(dirname "\$0")/.." && pwd)"
export PYTHONHOME="\$_ROS2_PREFIX/python/usr"
export AMENT_PREFIX_PATH="\$_ROS2_PREFIX\${AMENT_PREFIX_PATH:+:\$AMENT_PREFIX_PATH}"
export CMAKE_PREFIX_PATH="\$_ROS2_PREFIX\${CMAKE_PREFIX_PATH:+:\$CMAKE_PREFIX_PATH}"
export COLCON_PREFIX_PATH="\$_ROS2_PREFIX\${COLCON_PREFIX_PATH:+:\$COLCON_PREFIX_PATH}"
export LD_LIBRARY_PATH="\$_ROS2_PREFIX/lib:\$PYTHONHOME/lib/${target_multiarch}\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export PYTHONPATH="\$_ROS2_PREFIX/lib/python${py_ver}/site-packages:\$_ROS2_PREFIX/local/lib/python${py_ver}/dist-packages:\$PYTHONHOME/lib/python${py_ver}/site-packages:\$PYTHONHOME/lib/python3/dist-packages\${PYTHONPATH:+:\$PYTHONPATH}"
exec "\$PYTHONHOME/bin/python${py_ver}" "\$@"
EOF
  chmod +x "$install_base/bin/python3"
  if [ ! -e "$install_base/bin/python${py_ver}" ]; then
    ln -s python3 "$install_base/bin/python${py_ver}"
  fi
  find "$install_base/bin" "$install_base/lib" -type f -exec grep -Il '^#!/usr/bin/python3$' {} + 2>/dev/null \
    | while read -r script; do
        sed -i '1s|^#!/usr/bin/python3$|#!/usr/bin/env python3|' "$script"
      done || true

  echo "[INFO] 已打包 Python ${py_ver} 运行时"
}

package_opencv_runtime() {
  local install_base=$1 opencv_dir=$2 lib
  [ "$ENABLE_VISION" = true ] || return 0

  for lib in "$opencv_dir"/lib/libopencv_*.so.*; do
    [ -f "$lib" ] || continue
    cp -a "$lib" "$install_base/lib/"
  done
  echo "[INFO] 已打包 OpenCV 运行时"
}

package_runtime() {
  local install_base=$1 py_ver=$2 opencv_dir=$3
  package_python_runtime "$install_base" "$py_ver"
  package_opencv_runtime "$install_base" "$opencv_dir"
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

  # Remove Python runtime artifacts left by a previous package_python_runtime call.
  # Colcon picks up install_base/bin/python3 and tries to execute target-arch ELF.
  rm -rf "$install_base/python"
  rm -f "$install_base/bin/python3"*
  rm -f "$install_base/ros2-env."*

  local features=""
  [ "$ENABLE_VISION" = true ] && features+="vision "
  [ "$ENABLE_CLI" = true ] && features+="cli"
  echo "[INFO] colcon build (${#TARGET_PKGS[@]} packages, ${features:-core}, arch: $TARGET_ARCH)..."

  local asio_include="$SRC_DIR/chriskohlhoff/asio/asio/include"
  local tinyxml2_dir="$SRC_DIR/ros2/tinyxml2_vendor/tinyxml2_src"

  # OpenCV: 从 thirdparty 获取
  local opencv_dir="${OPENCV_DIR:-$REPO_ROOT/../thirdparty/output/$TARGET_ARCH/opencv}"
  if [ ! -d "$opencv_dir" ]; then
    echo "[ERROR] OpenCV not found at $opencv_dir"
    echo "[HINT] Build thirdparty first: cd ../thirdparty && ./build.sh -t $TARGET_ARCH opencv"
    exit 1
  fi
  echo "[INFO] Using OpenCV from: $opencv_dir"

  local py_ver
  py_ver="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

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
    -DCV_BRIDGE_DISABLE_PYTHON=OFF
  )

  # Native builds use amd64 Boost.Python downloaded into the image without
  # installing it, because Ubuntu's multiarch dev packages conflict.
  if [ "$TARGET_ARCH" = "x86_64" ] && [ -d /opt/boost-python-amd64 ]; then
    local py_abi py_lib
    py_abi="${py_ver//./}"
    py_lib="$(find "/opt/boost-python-amd64/usr/lib/x86_64-linux-gnu" \
      -maxdepth 1 -name "libboost_python${py_abi}.so" -print -quit)"
    if [ -z "$py_lib" ]; then
      echo "[ERROR] Host Boost.Python ${py_ver} library not found"
      exit 1
    fi
    cmake_args+=(
      -DBoost_NO_BOOST_CMAKE=ON
      -DBoost_NO_SYSTEM_PATHS=ON
      -DBOOST_ROOT=/usr
      -DBoost_INCLUDE_DIR=/usr/include
      -DBoost_LIBRARY_DIR_RELEASE="$(dirname "$py_lib")"
      -DBoost_PYTHON3_LIBRARY_RELEASE="$py_lib"
      -DBoost_PYTHON3_VERSION=312
    )
  fi

  # Cross-compile: add toolchain
  if [ "$TARGET_ARCH" != "$(uname -m)" ]; then
    local toolchain="$REPO_ROOT/toolchain/aarch64-linux-gnu.cmake"
    local cross_python="$REPO_ROOT/toolchain/python3-aarch64"
    if [ ! -f "$toolchain" ]; then
      toolchain="/opt/toolchain/aarch64-linux-gnu.cmake"
      cross_python="/opt/toolchain/python3-aarch64"
    fi
    cmake_args+=(
      -DCMAKE_TOOLCHAIN_FILE="$toolchain"
      -DPython3_EXECUTABLE="$cross_python"
      -DPYTHON_EXECUTABLE="$cross_python"
    )
    echo "[INFO] 使用交叉编译 toolchain: $toolchain"
    cmake_args+=("-DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath-link,$install_base/lib")
    cmake_args+=("-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-rpath-link,$install_base/lib")
  fi

  colcon --log-base "$log_base" build \
    --build-base "$build_base" \
    --install-base "$install_base" \
    --merge-install \
    --cmake-args "${cmake_args[@]}" \
    --no-warn-unused-cli \
    --packages-up-to "${TARGET_PKGS[@]}"

  package_runtime "$install_base" "$py_ver" "$opencv_dir"

  echo "[INFO] 打包 $TARBALL..."
  local strip_tool="strip"
  if [ "$TARGET_ARCH" != "$(uname -m)" ]; then
    strip_tool="${TARGET_ARCH}-linux-gnu-strip"
    command -v "$strip_tool" >/dev/null 2>&1 || strip_tool="strip"
  fi
  echo "[INFO] Strip ELF binaries ($strip_tool)..."
  find "$install_base" -type f \( -name "*.so" -o -name "*.so.*" -o -perm -u+x -o -path "*/bin/*" \) -print0 \
    | while IFS= read -r -d '' f; do
        if [ "$(head -c 4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]; then
          "$strip_tool" --strip-all "$f" 2>/dev/null || true
        fi
      done

  mkdir -p "$arch_dir"
  tar czf "$arch_dir/$TARBALL" -C "$install_base" .

  local size
  size="$(du -sh "$arch_dir/$TARBALL" | cut -f1)"
  echo "[OK] 产物: $arch_dir/$TARBALL ($size)"
}

# ─── Docker 模式 ───

docker_preflight() {
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

get_image_name() {
  echo "ros2-core/${DISTRO}:dev"
}

docker_build_base_image() {
  local base_image
  base_image="$(get_image_name)"

  if docker image inspect "$base_image" &>/dev/null && [ -z "$NO_CACHE" ]; then
    echo "[OK] 复用缓存 base 镜像: $base_image"
  else
    echo "[INFO] 构建 base 镜像: $base_image ..."
    docker build $NO_CACHE \
      --target "$DISTRO" \
      -t "$base_image" \
      -f "$REPO_ROOT/Dockerfile" \
      "$REPO_ROOT"
    echo "[OK] base 镜像已缓存: $base_image"
  fi
}

sync_prebuilt() {
  local name=$1 src=$2 dst=$3 check_file=$4
  mkdir -p "$dst"

  if [ ! -d "$src" ]; then
    echo "[ERROR] $name not found at $src"
    echo "[HINT] Build thirdparty first: cd ../thirdparty && ./build.sh -t $TARGET_ARCH $name"
    exit 1
  fi

  if [ ! -f "$check_file" ] || [ "$src/$check_file" -nt "$check_file" ] 2>/dev/null; then
    echo "[INFO] Copying $name to prebuilt/$TARGET_ARCH/$name"
    rm -rf "$dst"
    cp -a "$src" "$dst"
  else
    echo "[INFO] Using cached $name from prebuilt/$TARGET_ARCH/$name"
  fi
}

docker_do_build() {
  local base_image
  base_image="$(get_image_name)"

  local prebuilt_opencv="$REPO_ROOT/prebuilt/$TARGET_ARCH/opencv"
  local prebuilt_libcurl="$REPO_ROOT/prebuilt/$TARGET_ARCH/libcurl"
  local thirdparty_opencv="$REPO_ROOT/../thirdparty/output/$TARGET_ARCH/opencv"
  local thirdparty_libcurl="$REPO_ROOT/../thirdparty/output/$TARGET_ARCH/libcurl"

  sync_prebuilt "opencv" "$thirdparty_opencv" "$prebuilt_opencv" "lib/libopencv_core.so"
  sync_prebuilt "libcurl" "$thirdparty_libcurl" "$prebuilt_libcurl" "lib/libcurl.so"

  local clean_arg=()
  [ "$CLEAN_BUILD" = true ] && clean_arg=(-c)

  echo "[INFO] Docker 编译 (arch: $TARGET_ARCH${clean_arg:+, clean build})..."

  docker run --rm \
    --network host \
    -e http_proxy="${http_proxy:-}" \
    -e https_proxy="${https_proxy:-}" \
    -e no_proxy="${no_proxy:-}" \
    -e OPENCV_DIR=/opt/opencv \
    -e CURL_DIR=/opt/libcurl \
    -e _ROS2_BUILD_IN_DOCKER=1 \
    -u "$(id -u):$(id -g)" \
    -v "$REPO_ROOT:/ws" \
    -v "$prebuilt_opencv:/opt/opencv:ro" \
    -v "$prebuilt_libcurl:/opt/libcurl:ro" \
    "$base_image" \
    bash /ws/scripts/build.sh "$DISTRO" --arch "$TARGET_ARCH" --in-docker \
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

# ─── 全编译模式 ───

build_all() {
  local builds=(
    "humble x86_64"
    "humble aarch64"
    "jazzy x86_64"
    "jazzy aarch64"
  )
  local results=() tarballs=() failed=0
  local start_all
  start_all=$(date +%s)

  for entry in "${builds[@]}"; do
    local distro arch
    read -r distro arch <<< "$entry"
    local tb="$REPO_ROOT/output/$distro/$arch/ros2-${distro}-${arch}.tar.gz"

    echo ""
    echo "############################################################"
    echo "## 全编译 [$distro $arch]"
    echo "############################################################"

    local clean_flag=()
    [ "$CLEAN_BUILD" = true ] && clean_flag=(-c)

    if bash "$SCRIPT_DIR/build.sh" "$distro" -t "$arch" ${NO_CACHE:+"$NO_CACHE"} "${clean_flag[@]}"; then
      local sz
      sz="$(du -sh "$tb" 2>/dev/null | cut -f1)"
      results+=("  ✅ $distro $arch  $(printf '%6s' "${sz:-?}")")
      tarballs+=("$tb")
    else
      results+=("  ❌ $distro $arch  FAILED")
      failed=1
    fi
  done

  local all_elapsed
  all_elapsed=$(($(date +%s) - start_all))

  echo ""
  echo "=========================================="
  echo " 全编译结果"
  echo "=========================================="
  printf '%s\n' "${results[@]}"
  printf '[OK] 总耗时: %d分%d秒\n' $((all_elapsed / 60)) $((all_elapsed % 60))

  if [ $failed -eq 1 ]; then
    echo ""
    echo "[WARN] 部分编译失败，请检查上述 ❌ 项。"
    return 1
  fi

  # Collect all tarballs into a single staging directory for easy upload.
  local staging_dir="$REPO_ROOT/output/release"
  rm -rf "$staging_dir"
  mkdir -p "$staging_dir"
  for tb in "${tarballs[@]}"; do
    cp "$tb" "$staging_dir/"
  done

  echo ""
  echo "=========================================="
  echo " 发布目录"
  echo "=========================================="
  echo "  $staging_dir/"
  ls -lh "$staging_dir"/ros2-*.tar.gz | awk '{print "  " $NF, "("$5")"}'

  echo ""
  echo "=========================================="
  echo " GitHub Release 操作指引"
  echo "=========================================="
  echo ""
  echo "  请将 VERSION 文件中的版本号同步为 tag:"
  echo "    cat VERSION"
  echo ""
  echo "  创建 Release 并上传所有 tarball:"
  echo "    gh release create \"\$(cat VERSION)\" \\"
  for tb in "${tarballs[@]}"; do
    echo "      \"output/release/$(basename "$tb")\" \\"
  done
  echo "      --title \"\$(cat VERSION)\" \\"
  echo "      --notes \"Release notes\""
}

# ─── 主流程 ───

parse_args "$@"

START_TIME=$(date +%s)

if [ "$BUILD_ALL" = true ]; then
  build_all
  exit $?
fi

case "$BUILD_MODE" in
  docker)
    echo "=========================================="
    echo " Docker 编译 ROS2 ${DISTRO^^} (${TARGET_ARCH})"
    echo "=========================================="
    mkdir -p "$OUTPUT_DIR"
    docker_preflight
    docker_build_base_image
    docker_do_build
    ;;
  native)
    preflight_check
    echo "=========================================="
    echo " 编译 ROS2 ${DISTRO^^} (${TARGET_ARCH})"
    echo "=========================================="
    clean_env
    cd "$SRC_DIR"
    mark_ignore_pkgs
    do_build
    ;;
  in-docker)
    preflight_check
    echo "=========================================="
    echo " 编译 ROS2 ${DISTRO^^} (${TARGET_ARCH})"
    echo "=========================================="
    clean_env
    cd "$SRC_DIR"
    mark_ignore_pkgs
    do_build
    ;;
esac

ELAPSED=$(($(date +%s) - START_TIME))
printf "[OK] 总耗时: %d分%d秒\n" $((ELAPSED / 60)) $((ELAPSED % 60))
