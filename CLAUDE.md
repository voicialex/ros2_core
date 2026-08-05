# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ros2_core packages the ROS2 components used by [buddy_robot](https://github.com/voicialex/buddy) into self-contained tarballs. The default package supports C++, Python/rclpy, ROS 2 CLI, FastDDS, and vision (`cv_bridge`, `image_transport`, `v4l2_camera`) for Humble (Ubuntu 22.04) and Jazzy (Ubuntu 24.04).

ARM64 packages target the J6M development board. J6M is aarch64 Debian 12 with a PREEMPT_RT kernel; it has no system Python 3.10 or matching OpenCV runtime. The package therefore carries the required Python and OpenCV runtime libraries.

## Common Commands

```bash
# Pull/update ROS2 + vendor 上游源码（均在 repos/<distro>*.repos 声明）
./scripts/update_src.sh jazzy    # or humble

# Build (默认在 Docker 容器内编译，加 --native 才在宿主机直接编译)
./scripts/build.sh jazzy                     # Docker x86_64
./scripts/build.sh humble -t arm64           # Docker aarch64 cross-build for J6M
./scripts/build.sh humble -t arm64 --no-cache  # 重建镜像后交叉编译
./scripts/build.sh humble --native           # 宿主机直接编译
./scripts/build.sh --all                     # 全编译 humble/jazzy × x86_64/aarch64

# Release
git tag vYYYY.MM.N && git push --tags
```

`./scripts/build.sh -t arm64` 的 Host 只负责调度 Docker、挂载源码和复制 thirdparty 依赖；ROS2 的 CMake/colcon 编译、链接、strip 和 tarball 打包均在 Docker 容器内执行。容器使用 `aarch64-linux-gnu-gcc/g++` 交叉编译器，不在 J6M 上本地编译。

## Repository Structure

- `repos/humble.repos`, `repos/jazzy.repos` — vcstool manifests (single source of truth for which repos to vendor).
- `src/humble/`, `src/jazzy/` — Vendored ROS2 source trees, committed to git. Synced declaratively from `.repos` files via `update_src.sh`.
- `scripts/update_src.sh` — Declarative sync: adds new repos, removes stale ones, cleans nested `.git` dirs.
- `scripts/build.sh` — 统一编译入口：默认走 Docker（推荐），`--native` 在宿主机直接编译。包含 colcon build、aarch64 toolchain、运行时收集和 tarball 打包。
- `Dockerfile` — Multi-stage build for Humble (22.04) and Jazzy (24.04), with BuildKit caches for apt and pip downloads.
- `toolchain/aarch64-linux-gnu.cmake` — aarch64 cross-compilation toolchain and target Python ABI settings.
- `toolchain/python3-aarch64` — Host-executable Python metadata proxy used to produce aarch64 extension suffixes during cross-compilation.
- `prebuilt/<arch>/` — Host-provided thirdparty OpenCV and libcurl trees mounted read-only into Docker builds.
- `output/<distro>/<arch>/` — Build and package output; generated files are not source of truth.

## Key Build Details

- Build tool: **colcon** with CMake. Args: `-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DTRACETOOLS_DISABLED=ON --no-warn-unused-cli`.
- Target modules: core C++ packages, `rclpy`, ROS 2 CLI packages, vision packages, and their generated message/type support dependencies.
- Middleware: FastDDS only (`rmw_fastrtps`; no Connext/Cyclone).
- Python: Humble uses Python 3.10; Jazzy uses Python 3.12. ARM64 Python extensions must use the target suffix (`cpython-310-aarch64-linux-gnu` or `cpython-312-aarch64-linux-gnu`), not the host x86_64 suffix.
- Runtime packaging: ARM64/AMD64 Python runtime debs, NumPy/YAML dependencies, OpenCV libraries, Boost.Python, BLAS/Fortran libraries, and OpenCV's WebP libraries are collected into the tarball.
- Shell environments: standard Linux Bash uses `ros2-env.sh`; J6M uses `ros2-env.zsh` because J6M links `/bin/bash` to zsh and cannot source Bash-specific ROS setup scripts reliably.
- Docker caching: Dockerfile uses BuildKit cache mounts for `/var/cache/apt`, `/var/lib/apt/lists`, and `/root/.cache/pip`. `--no-cache` rebuilds image layers but preserves BuildKit download caches.
- Skipped via COLCON_IGNORE: `test_msgs`, `test_interface_files`, `ros2cli_test_interfaces`.
- Repo counts: Humble 33, Jazzy 35 (Jazzy adds `rosidl_core`, `rosidl_dynamic_typesupport*`).
- Output: `output/<distro>/<arch>/ros2-<distro>-<arch>.tar.gz`.
- Versioning: `VERSION` file contains `vYYYY.MM.N`; pushing a matching tag triggers `.github/workflows/release.yml` which Docker-builds both distros and publishes to GitHub Releases.

## J6M Validation

Do not install the test package into system directories. Use `/tmp` for temporary validation and `/app` for a persistent deployment; `/middleware` is nearly full on the board.

```bash
# Host
cat output/humble/aarch64/ros2-humble-aarch64.tar.gz \\
  | pkixssh root@192.168.2.62 'cat > /tmp/ros2-humble-aarch64.tar.gz'

# J6M
rm -rf /tmp/ros2-humble-aarch64-test
mkdir -p /tmp/ros2-humble-aarch64-test
tar xzf /tmp/ros2-humble-aarch64.tar.gz -C /tmp/ros2-humble-aarch64-test
cd /tmp/ros2-humble-aarch64-test
source ros2-env.zsh
python3 --version
ros2 --help
python3 -c 'import rclpy; from sensor_msgs.msg import Image; import cv_bridge'
```

## Shell Script Conventions

- All scripts use `set -euo pipefail` and take distro (`humble`|`jazzy`) as first positional arg.
- Scripts are idempotent — safe to re-run without side effects.
- Env vars: `REPO_ROOT`, `OUTPUT_DIR`, `DISTRO` (uppercase).
- Keep generated build/install/log trees out of source changes; modify source manifests, scripts, Dockerfile, and toolchain files instead.
