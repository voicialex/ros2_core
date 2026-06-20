# Dockerfile — ROS2 核心编译环境 (FastDDS only)
# 每个 distro 一个统一镜像，同时支持 x86 native 和 arm64 cross-compile
#
# 用法: ./scripts/docker_build.sh jazzy
#       ./scripts/docker_build.sh humble

# ─── Jazzy (Ubuntu 24.04, x86 native + arm64 cross) ───
FROM ubuntu:24.04 AS jazzy
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/ubuntu.sources \
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
        libssl-dev:arm64 \
        libpython3-dev:arm64 \
        libwebp-dev:arm64 \
        libyaml-cpp-dev:arm64 \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/lib/python3*/EXTERNALLY-MANAGED \
    && pip3 install --break-system-packages colcon-common-extensions vcstool
COPY toolchain/ /opt/toolchain/

# ─── Humble (Ubuntu 22.04, x86 native + arm64 cross) ───
FROM ubuntu:22.04 AS humble
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list \
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
        libssl-dev:arm64 \
        libpython3-dev:arm64 \
        libwebp-dev:arm64 \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install colcon-common-extensions vcstool 'empy<4' \
    # Fix: libpython3-dev:arm64 may not install multiarch pyconfig.h on Ubuntu 22.04.
    # The stub pyconfig.h at /usr/include/python3.10/ redirects to the arch-specific
    # file, so we need /usr/include/aarch64-linux-gnu/python3.10/pyconfig.h to exist.
    && apt-get update && apt-get download libpython3.10-dev:arm64 \
    && mkdir -p /tmp/py-arm64 /usr/include/aarch64-linux-gnu/python3.10 \
    && dpkg -x libpython3.10-dev_*.deb /tmp/py-arm64 \
    && _pyconfig_src="$(find /tmp/py-arm64 -name pyconfig.h -path '*aarch64*' | head -1)" \
    && [ -n "$_pyconfig_src" ] || _pyconfig_src="$(find /tmp/py-arm64 -name pyconfig.h | head -1)" \
    && cp "$_pyconfig_src" /usr/include/aarch64-linux-gnu/python3.10/pyconfig.h \
    && rm -rf /tmp/py-arm64 libpython3.10-dev_*.deb /var/lib/apt/lists/*
COPY toolchain/ /opt/toolchain/
