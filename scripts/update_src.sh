#!/usr/bin/env bash
set -euo pipefail

DISTRO="${1:?用法: $0 humble|jazzy}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_FILE="$REPO_ROOT/repos/${DISTRO}.repos"
SRC_DIR="$REPO_ROOT/src/$DISTRO"

if [ ! -f "$REPOS_FILE" ]; then
    echo "repos 文件不存在: $REPOS_FILE"
    exit 1
fi

if ! command -v vcs &>/dev/null; then
    pip3 install --break-system-packages vcstool
fi

mkdir -p "$SRC_DIR"
echo "[INFO] 拉取 $DISTRO 源码..."
vcs import "$SRC_DIR" < "$REPOS_FILE"

find "$SRC_DIR" -name ".git" -type d -exec rm -rf {} +

COUNT=$(ls "$SRC_DIR" | wc -l)
echo "[OK] 已拉取 $COUNT 个仓库到 src/$DISTRO"
echo "请 git add src/$DISTRO/ && git commit"
