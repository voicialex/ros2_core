# ros2_core

Pre-built ROS2 core libraries for [buddy_robot](https://github.com/voicialex/buddy).

## Releases

Download from [GitHub Releases](https://github.com/voicialex/ros2_core/releases).

Assets:
- `ros2-humble-x86_64.tar.gz` — ROS2 Humble (Ubuntu 22.04)
- `ros2-jazzy-x86_64.tar.gz` — ROS2 Jazzy (Ubuntu 24.04)

## Update source

```bash
./scripts/update_src.sh jazzy    # or humble
git add src/jazzy/ && git commit
git tag vYYYY.MM.N && git push --tags
```

CI will build and publish automatically.
