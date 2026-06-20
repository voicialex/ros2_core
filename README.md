# ros2_core

Pre-built ROS2 core libraries for [buddy_robot](https://github.com/voicialex/buddy).

## Releases

Download from [GitHub Releases](https://github.com/voicialex/ros2_core/releases).

Assets:
- `ros2-humble-x86_64.tar.gz` — ROS2 Humble (Ubuntu 22.04)
- `ros2-jazzy-x86_64.tar.gz` — ROS2 Jazzy (Ubuntu 24.04)

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
