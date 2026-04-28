# Dockerfile — 在干净 Ubuntu 环境中编译 ROS2 核心 (FastDDS only)
# 用法:
#   ./scripts/docker_build.sh jazzy
#   ./scripts/docker_build.sh humble -o /tmp

ARG DISTRO=jazzy

# ─── Jazzy (Ubuntu 24.04) ───
FROM ubuntu:24.04 AS build-jazzy
ARG DISTRO=jazzy
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git python3-colcon-common-contents \
        libasio-dev libssl-dev libtinyxml2-dev libyaml-dev \
        libpoco-dev libconsole-bridge-dev libspdlog-dev \
    && rm -rf /var/lib/apt/lists/*
COPY src/jazzy /ws/src
RUN cd /ws/src && \
    colcon build \
        --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
        --packages-up-to \
            rclcpp_components rclcpp_lifecycle \
            std_msgs sensor_msgs builtin_interfaces \
            rosidl_default_generators \
    && tar czf /ros2-jazzy-x86_64.tar.gz -C install .

# ─── Humble (Ubuntu 22.04) ───
FROM ubuntu:22.04 AS build-humble
ARG DISTRO=humble
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git python3-colcon-common-contents \
        libasio-dev libssl-dev libtinyxml2-dev libyaml-dev \
        libpoco-dev libconsole-bridge-dev libspdlog-dev \
    && rm -rf /var/lib/apt/lists/*
COPY src/humble /ws/src
RUN cd /ws/src && \
    colcon build \
        --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
        --packages-up-to \
            rclcpp_components rclcpp_lifecycle \
            std_msgs sensor_msgs builtin_interfaces \
            rosidl_default_generators \
    && tar czf /ros2-humble-x86_64.tar.gz -C install .

# ─── Export (jazzy 默认) ───
FROM scratch AS export-jazzy
COPY --from=build-jazzy /ros2-jazzy-*.tar.gz /

FROM scratch AS export-humble
COPY --from=build-humble /ros2-humble-*.tar.gz /

FROM export-jazzy AS export
