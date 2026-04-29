# Repository Guidelines

## Project Structure & Module Organization
- `src/<distro>/`: vendored ROS2 source trees, currently `humble` and `jazzy`.
- `repos/*.repos`: source manifests used by `vcs import`.
- `scripts/`: operational entrypoints:
  - `update_src.sh` refreshes source snapshots.
  - `build.sh` performs native `colcon` builds and packaging.
  - `docker_build.sh` builds in a clean Docker environment.
- `.github/workflows/release.yml`: CI pipeline that builds tarballs and publishes releases.
- `output/<distro>/`: local build artifacts (generated, do not treat as source).

## Build, Test, and Development Commands
- `./scripts/update_src.sh jazzy` (or `humble`): import repositories from `repos/<distro>.repos` into `src/<distro>/`.
- `./scripts/build.sh jazzy`: native build and package to `output/jazzy/ros2-jazzy-<arch>.tar.gz`.
- `./scripts/docker_build.sh jazzy`: reproducible container build; preferred when host toolchains differ.
- `colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF`: baseline build mode used by CI.

## Coding Style & Naming Conventions
- Shell scripts use `bash` with `set -euo pipefail` and explicit argument validation.
- Keep scripts idempotent and distro-driven (`humble|jazzy` as the first positional argument).
- Use clear uppercase environment variable names (`REPO_ROOT`, `OUTPUT_DIR`, `DISTRO`).
- Preserve existing directory naming: distro paths in lowercase, release artifacts as `ros2-<distro>-<arch>.tar.gz`.

## Testing Guidelines
- This repository is build-validation focused; CI currently compiles with `BUILD_TESTING=OFF` for release artifacts.
- For package-level verification when needed:
  - `colcon test --test-result-base output/<distro>/test`
  - `colcon test-result --verbose`
- Validate both distros when changing build logic or manifests.

## Commit & Pull Request Guidelines
- Follow the established commit format seen in history:
  - `feat(module): [PRO-10000] <Imperative English summary>`
  - Example: `feat(build): [PRO-10000] Add Docker cache reuse`
- Keep each PR scoped to one concern (source update, build logic, or CI).
- PR description should include:
  - target distro(s) (`humble`, `jazzy`),
  - commands run locally,
  - artifact path or release impact.
