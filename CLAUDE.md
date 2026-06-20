# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ros2_core is a minimal C++ ROS2 core library packaging repo for [buddy_robot](https://github.com/voicialex/buddy). It vendors only the ROS2 packages needed for C++ development (Humble for Ubuntu 22.04, Jazzy for Ubuntu 24.04), compiles them into self-contained tarballs, and publishes via GitHub Releases.

## Common Commands

```bash
# Pull/update ROS2 + vendor 上游源码（均在 repos/<distro>*.repos 声明）
./scripts/update_src.sh jazzy    # or humble

# Build (默认 Docker，加 --native 在宿主机直接编译)
./scripts/build.sh jazzy                     # Docker x86_64
./scripts/build.sh humble -t arm64           # Docker 交叉编译 aarch64
./scripts/build.sh humble -t arm64 --no-cache  # 重建镜像后交叉编译
./scripts/build.sh humble --native           # 宿主机直接编译

# Release
git tag vYYYY.MM.N && git push --tags
```

## Repository Structure

- `repos/humble.repos`, `repos/jazzy.repos` — vcstool manifests (single source of truth for which repos to vendor).
- `src/humble/`, `src/jazzy/` — Vendored ROS2 source trees, committed to git. Synced declaratively from `.repos` files via `update_src.sh`.
- `scripts/update_src.sh` — Declarative sync: adds new repos, removes stale ones, cleans nested `.git` dirs.
- `scripts/build.sh` — 统一编译入口：默认走 Docker（推荐），`--native` 在宿主机直接编译。含 colcon compile、交叉编译 toolchain、打包 tarball。
- `Dockerfile` — Multi-stage build for Humble (22.04) and Jazzy (24.04).

## Key Build Details

- Build tool: **colcon** with cmake. Args: `-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DTRACETOOLS_DISABLED=ON --no-warn-unused-cli`.
- Target packages: `rclcpp_components`, `rclcpp_lifecycle`, `std_msgs`, `sensor_msgs`, `builtin_interfaces`, `rosidl_default_generators`.
- Skipped via COLCON_IGNORE: `test_msgs`, `test_interface_files`.
- Middleware: FastDDS only (no Connext/Cyclone).
- Repo counts: Humble 33, Jazzy 35 (Jazzy adds `rosidl_core`, `rosidl_dynamic_typesupport*`).
- Output: `output/<distro>/ros2-<distro>-<arch>.tar.gz`.
- Versioning: `VERSION` file contains `vYYYY.MM.N`; pushing a matching tag triggers `.github/workflows/release.yml` which Docker-builds both distros and publishes to GitHub Releases.

## Shell Script Conventions

- All scripts use `set -euo pipefail` and take distro (`humble`|`jazzy`) as first positional arg.
- Scripts are idempotent — safe to re-run without side effects.
- Env vars: `REPO_ROOT`, `OUTPUT_DIR`, `DISTRO` (uppercase).
