# syntax=docker/dockerfile:1
# Dockerfile — ROS2 核心编译环境 (FastDDS only)
# 每个 distro 一个统一镜像，同时支持 x86 native 和 arm64 cross-compile
#
# 用法: ./scripts/docker_build.sh jazzy
#       ./scripts/docker_build.sh humble
# ─── Jazzy (Ubuntu 24.04, x86 native + arm64 cross) ───
FROM ubuntu:24.04 AS jazzy
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists \
    sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/ubuntu.sources \
    && dpkg --add-architecture arm64 \
    && echo "deb [arch=arm64] http://mirrors.aliyun.com/ubuntu-ports noble main restricted universe multiverse" > /etc/apt/sources.list.d/arm64.list \
    && echo "deb [arch=arm64] http://mirrors.aliyun.com/ubuntu-ports noble-updates main restricted universe multiverse" >> /etc/apt/sources.list.d/arm64.list \
    && sed -i 's|^Types: deb|Types: deb\nArchitectures: amd64|' /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git python3-pip python3-venv python3-dev python3-numpy pkg-config \
        python3-lark python3-yaml python3-empy python3-catkin-pkg \
        libboost-dev libwebp-dev \
        # Cross-compiler
        gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
        libboost-dev:arm64 \
        libboost-python-dev:arm64 \
        libssl-dev:arm64 \
        libpython3-dev:arm64 \
        libwebp-dev:arm64 \
        libyaml-cpp-dev:arm64 \
    && rm -f /usr/lib/python3*/EXTERNALLY-MANAGED
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --break-system-packages colcon-common-extensions vcstool

# Keep target Python runtime debs for self-contained ROS2 tarballs.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists \
    mkdir -p /opt/ros2-runtime-debs/amd64 /opt/ros2-runtime-debs/arm64 \
    && apt-get update \
    && cd /opt/ros2-runtime-debs/amd64 \
    && apt-get download \
        python3.12-minimal:amd64 libpython3.12-minimal:amd64 \
        libpython3.12-stdlib:amd64 libpython3.12:amd64 python3.12:amd64 \
        python3-numpy:amd64 python3-yaml:amd64 python3-netifaces:amd64 \
        libmpdec3:amd64 libblas3:amd64 liblapack3:amd64 libgfortran5:amd64 libyaml-0-2:amd64 \
    && cd /opt/ros2-runtime-debs/arm64 \
    && apt-get download \
        python3.12-minimal:arm64 libpython3.12-minimal:arm64 \
        libpython3.12-stdlib:arm64 libpython3.12:arm64 python3.12:arm64 \
        python3-numpy:arm64 python3-yaml:arm64 python3-netifaces:arm64 \
        libmpdec3:arm64 libblas3:arm64 liblapack3:arm64 libgfortran5:arm64 libyaml-0-2:arm64
COPY toolchain/ /opt/toolchain/

# ─── Humble (Ubuntu 22.04, x86 native + arm64 cross) ───
FROM ubuntu:22.04 AS humble
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists \
    sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list \
    && dpkg --add-architecture arm64 \
    && sed -i 's|^deb |deb [arch=amd64] |g' /etc/apt/sources.list \
    && echo "deb [arch=arm64] http://mirrors.aliyun.com/ubuntu-ports jammy main restricted universe multiverse" >> /etc/apt/sources.list \
    && echo "deb [arch=arm64] http://mirrors.aliyun.com/ubuntu-ports jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git python3-pip python3-dev python3-numpy pkg-config \
        python3-lark python3-yaml python3-empy python3-catkin-pkg \
        libboost-dev libwebp-dev \
        # Cross-compiler
        gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
        libc6-dev-arm64-cross \
        libboost-dev:arm64 \
        libboost-python-dev:arm64 \
        libssl-dev:arm64 \
        libpython3-dev:arm64 \
        libwebp-dev:arm64
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install colcon-common-extensions vcstool 'empy<4'
# Fix: libpython3-dev:arm64 may not install multiarch pyconfig.h on Ubuntu 22.04.
# The stub pyconfig.h at /usr/include/python3.10/ redirects to the arch-specific
# file, so we need /usr/include/aarch64-linux-gnu/python3.10/pyconfig.h to exist.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update && apt-get download libpython3.10-dev:arm64 \
    && mkdir -p /tmp/py-arm64 /usr/include/aarch64-linux-gnu/python3.10 \
    && dpkg -x libpython3.10-dev_*.deb /tmp/py-arm64 \
    && _pyconfig_src="$(find /tmp/py-arm64 -name pyconfig.h -path '*aarch64*' | head -1)" \
    && [ -n "$_pyconfig_src" ] || _pyconfig_src="$(find /tmp/py-arm64 -name pyconfig.h | head -1)" \
    && cp "$_pyconfig_src" /usr/include/aarch64-linux-gnu/python3.10/pyconfig.h \
    && rm -rf /tmp/py-arm64 libpython3.10-dev_*.deb

# Keep target Python runtime debs for self-contained ROS2 tarballs.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists \
    mkdir -p /opt/ros2-runtime-debs/amd64 /opt/ros2-runtime-debs/arm64 \
    && apt-get update \
    && cd /opt/ros2-runtime-debs/amd64 \
    && apt-get download \
        python3.10-minimal:amd64 libpython3.10-minimal:amd64 \
        libpython3.10-stdlib:amd64 libpython3.10:amd64 python3.10:amd64 \
        python3-numpy:amd64 python3-yaml:amd64 python3-netifaces:amd64 \
        libmpdec3:amd64 libblas3:amd64 liblapack3:amd64 libgfortran5:amd64 libyaml-0-2:amd64 \
    && cd /opt/ros2-runtime-debs/arm64 \
    && apt-get download \
        python3.10-minimal:arm64 libpython3.10-minimal:arm64 \
        libpython3.10-stdlib:arm64 libpython3.10:arm64 python3.10:arm64 \
        python3-numpy:arm64 python3-yaml:arm64 python3-netifaces:arm64 \
        libmpdec3:arm64 libblas3:arm64 liblapack3:arm64 libgfortran5:arm64 libyaml-0-2:arm64
COPY toolchain/ /opt/toolchain/
