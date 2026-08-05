# ros2_core

Pre-built ROS2 core libraries for [buddy_robot](https://github.com/voicialex/buddy).

## Releases

Download from [GitHub Releases](https://github.com/voicialex/ros2_core/releases).

Assets:
- `ros2-humble-x86_64.tar.gz` — ROS2 Humble (Ubuntu 22.04)
- `ros2-humble-aarch64.tar.gz` — ROS2 Humble (ARM64)
- `ros2-jazzy-x86_64.tar.gz` — ROS2 Jazzy (Ubuntu 24.04)
- `ros2-jazzy-aarch64.tar.gz` — ROS2 Jazzy (ARM64)

每个产物默认包含 FastDDS、C++ API、vision（`cv_bridge` / `image_transport` /
`v4l2_camera`）、ROS 2 CLI 和 rclpy。Python 与 OpenCV 运行时随包提供，不依赖
目标机预装的同版本 Python 或 OpenCV。

## Deploy on ARM64

```bash
mkdir -p /app/ros2
# 解压对应发行版的 aarch64 tarball 到 /app/ros2
cd /app/ros2
# 常规 Linux Bash
source ros2-env.sh
# J6M 当前将 /bin/bash 链接到 zsh，改用：source ros2-env.zsh

python3 --version
ros2 --help
python3 -c 'import rclpy; from sensor_msgs.msg import Image; import cv_bridge'
```

请通过 `source ros2-env.sh` 使用 Python CLI / rclpy；它会启用包内 Python 并隔离
目标机自带的 Python。C++ 节点仅需 `source setup.bash`。

## Build

需要 Docker。默认编译 humble x86_64，加 `--native` 在宿主机直接编译。

```bash
./scripts/build.sh                        # Docker 编译 humble x86_64
./scripts/build.sh -t arm64               # Docker 交叉编译 humble aarch64
./scripts/build.sh -t arm64 --no-cache    # 重建镜像后交叉编译
./scripts/build.sh --native               # 宿主机直接编译
./scripts/build.sh jazzy --native         # 宿主机编译 jazzy x86_64
./scripts/build.sh --all                  # 全编译 4 个 tarball（发版用）
```

## Update source

```bash
./scripts/update_src.sh jazzy    # or humble
git add src/jazzy/ && git commit
git tag vYYYY.MM.N && git push --tags
```

CI will build and publish automatically.
