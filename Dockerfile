# Dockerfile — 在干净 Ubuntu 环境中编译 ROS2 核心 (FastDDS only)
# 用法:
#   ./scripts/docker_build.sh jazzy
#   ./scripts/docker_build.sh humble -o /tmp
#
# 镜像拉取: 使用 Docker daemon 配置的镜像加速器
# apt 源: 阿里云
#
# 结构: base-<distro> (依赖缓存) → build-<distro> (编译)

ARG DISTRO=jazzy

# ─── Jazzy Base (Ubuntu 24.04 依赖缓存) ───
FROM ubuntu:24.04 AS base-jazzy
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git python3-pip python3-venv python3-dev python3-numpy pkg-config \
        libasio-dev libssl-dev libtinyxml2-dev libyaml-dev \
        libpoco-dev libconsole-bridge-dev libspdlog-dev \
        liblttng-ust-dev \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/lib/python3*/EXTERNALLY-MANAGED \
    && pip3 install --break-system-packages colcon-common-extensions vcstool lark

# ─── Jazzy Build ───
FROM base-jazzy AS build-jazzy
COPY src/jazzy /ws/src
RUN cd /ws/src && \
    rm -rf ament/ament_lint ament/uncrustify_vendor ament/google_benchmark_vendor \
           ros2/mimick_vendor ros2/performance_test_fixture osrf/osrf_testing_tools_cpp && \
    colcon build \
        --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
        --packages-up-to \
            rclcpp_components rclcpp_lifecycle \
            std_msgs sensor_msgs builtin_interfaces \
            rosidl_default_generators \
    && tar czf /ros2-jazzy-x86_64.tar.gz -C install .

# ─── Humble Base (Ubuntu 22.04 依赖缓存) ───
FROM ubuntu:22.04 AS base-humble
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git python3-pip python3-dev python3-numpy pkg-config \
        libasio-dev libssl-dev libtinyxml2-dev libyaml-dev \
        libpoco-dev libconsole-bridge-dev libspdlog-dev \
        liblttng-ust-dev \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install colcon-common-extensions vcstool lark 'empy<4'

# ─── Humble Build ───
FROM base-humble AS build-humble
COPY src/humble /ws/src
RUN cd /ws/src && \
    rm -rf ament/ament_lint ament/uncrustify_vendor ament/google_benchmark_vendor \
           ros2/mimick_vendor ros2/performance_test_fixture osrf/osrf_testing_tools_cpp && \
    colcon build \
        --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
        --packages-up-to \
            rclcpp_components rclcpp_lifecycle \
            std_msgs sensor_msgs builtin_interfaces \
            rosidl_default_generators \
    && tar czf /ros2-humble-x86_64.tar.gz -C install .

# ─── Export ───
FROM scratch AS export-jazzy
COPY --from=build-jazzy /ros2-jazzy-*.tar.gz /

FROM scratch AS export-humble
COPY --from=build-humble /ros2-humble-*.tar.gz /

FROM export-jazzy AS export
