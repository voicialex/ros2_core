# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ros2_core is a minimal C++ ROS2 core library packaging repo for [buddy_robot](https://github.com/voicialex/buddy). It vendors only the ROS2 packages needed for C++ development (Humble for Ubuntu 22.04, Jazzy for Ubuntu 24.04), compiles them into self-contained tarballs, and publishes via GitHub Releases.

## Common Commands

```bash
# Pull/update ROS2 source packages (declarative sync from .repos)
./scripts/update_src.sh jazzy    # or humble

# Build locally (requires colcon, cmake, libasio-dev)
./scripts/build.sh jazzy
./scripts/build.sh humble -o /tmp

# Build in Docker (preferred — clean reproducible build)
./scripts/docker_build.sh jazzy
./scripts/docker_build.sh jazzy --no-cache
./scripts/docker_build.sh humble -c ~/buddy_robot

# Release
git tag vYYYY.MM.N && git push --tags
```

## Repository Structure

- `repos/humble.repos`, `repos/jazzy.repos` — vcstool manifests (single source of truth for which repos to vendor).
- `src/humble/`, `src/jazzy/` — Vendored ROS2 source trees, committed to git. Synced declaratively from `.repos` files via `update_src.sh`.
- `scripts/update_src.sh` — Declarative sync: adds new repos, removes stale ones, cleans nested `.git` dirs.
- `scripts/build.sh` — Native build: colcon compile → tarball. Functions: `parse_args`, `preflight_check`, `clean_env`, `mark_ignore_pkgs`, `do_build`, `deploy`.
- `scripts/docker_build.sh` — Docker build: two-stage (cached base image + build). Functions: `parse_args`, `preflight_check`, `build_base_image`, `do_build`, `deploy`.
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
