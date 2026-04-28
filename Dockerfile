# Build ROS2 core from source
# Usage:
#   docker build --build-arg DISTRO=jazzy --target export -o type=local,dest=./output .
#   docker build --build-arg DISTRO=humble --target export -o type=local,dest=./output .

ARG DISTRO=jazzy

# ─── Jazzy (Ubuntu 24.04) ───
FROM ubuntu:24.04 AS build-jazzy
RUN apt-get update && apt-get install -y \
        build-essential cmake git python3-pip \
        libssl-dev libtinyxml2-dev libcurl4-openssl-dev python3-yaml \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/lib/python3*/EXTERNALLY-MANAGED \
    && pip3 install colcon-common-extensions vcstool rosdep \
    && rosdep init || true && rosdep update
COPY src/jazzy /ws/src
RUN cd /ws && \
    rosdep install --from-paths src --ignore-src -y --skip-keys "python3" || true && \
    colcon build \
        --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
        --packages-up-to \
            rclcpp_lifecycle std_msgs sensor_msgs \
            builtin_interfaces rosidl_default_generators && \
    tar czf /ros2-jazzy-x86_64.tar.gz -C install .

# ─── Humble (Ubuntu 22.04) ───
FROM ubuntu:22.04 AS build-humble
RUN apt-get update && apt-get install -y \
        build-essential cmake git python3-pip \
        libssl-dev libtinyxml2-dev libcurl4-openssl-dev python3-yaml \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/lib/python3*/EXTERNALLY-MANAGED \
    && pip3 install colcon-common-extensions vcstool rosdep \
    && rosdep init || true && rosdep update
COPY src/humble /ws/src
RUN cd /ws && \
    rosdep install --from-paths src --ignore-src -y --skip-keys "python3" || true && \
    colcon build \
        --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
        --packages-up-to \
            rclcpp_lifecycle std_msgs sensor_msgs \
            builtin_interfaces rosidl_default_generators && \
    tar czf /ros2-humble-x86_64.tar.gz -C install .

# ─── Export stages ───
FROM scratch AS export-jazzy
COPY --from=build-jazzy /ros2-jazzy-*.tar.gz /

FROM scratch AS export-humble
COPY --from=build-humble /ros2-humble-*.tar.gz /

# Default export (jazzy)
FROM export-jazzy AS export
