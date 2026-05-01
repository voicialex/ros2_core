# Dockerfile — ROS2 核心编译环境 (FastDDS only)
# 只提供编译环境，编译逻辑由 build.sh 统一完成
#
# 用法: ./scripts/docker_build.sh jazzy
#       ./scripts/docker_build.sh humble

# ─── Jazzy Base (Ubuntu 24.04) ───
FROM ubuntu:24.04 AS base-jazzy
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git python3-pip python3-venv python3-dev python3-numpy pkg-config \
        python3-lark python3-yaml python3-empy python3-catkin-pkg \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/lib/python3*/EXTERNALLY-MANAGED \
    && pip3 install --break-system-packages colcon-common-extensions vcstool

# ─── Humble Base (Ubuntu 22.04) ───
FROM ubuntu:22.04 AS base-humble
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git python3-pip python3-dev python3-numpy pkg-config \
        python3-lark python3-yaml python3-empy python3-catkin-pkg \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install colcon-common-extensions vcstool 'empy<4'
