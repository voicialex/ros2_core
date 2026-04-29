#!/usr/bin/env bash
# update_src.sh — 以 repos/<distro>.repos 为唯一真相源，声明式同步 src/<distro>/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── 函数定义 ───

parse_args() {
    DISTRO="${1:?用法: $0 humble|jazzy}"
    case "$DISTRO" in
        humble|jazzy) ;;
        *) echo "错误: distro 必须是 humble 或 jazzy"; exit 1 ;;
    esac

    REPOS_FILE="$REPO_ROOT/repos/${DISTRO}.repos"
    SRC_DIR="$REPO_ROOT/src/$DISTRO"

    if [ ! -f "$REPOS_FILE" ]; then
        echo "错误: repos 文件不存在: $REPOS_FILE"; exit 1
    fi
}

ensure_vcstool() {
    command -v vcs &>/dev/null || pip3 install --break-system-packages vcstool
}

# 从 .repos 解析期望的 org/repo 路径列表
get_wanted_repos() {
    grep -E '^ {2}[a-zA-Z].*/' "$REPOS_FILE" | sed 's/: *$//' | tr -d ' '
}

# 删除 src/ 中不在 .repos 里的仓库目录
remove_stale_repos() {
    [ -d "$SRC_DIR" ] || return 0
    local wanted="$1"

    for org_dir in "$SRC_DIR"/*/; do
        [ -d "$org_dir" ] || continue
        local org
        org=$(basename "$org_dir")
        for repo_dir in "$org_dir"/*/; do
            [ -d "$repo_dir" ] || continue
            local path="$org/$(basename "$repo_dir")"
            if ! echo "$wanted" | grep -qx "$path"; then
                echo "[INFO] 移除不在 .repos 中的仓库: $path"
                rm -rf "$repo_dir"
            fi
        done
        rmdir "$org_dir" 2>/dev/null || true
    done
}

import_repos() {
    echo "[INFO] 同步 $DISTRO 源码..."
    vcs import --skip-existing "$SRC_DIR" < "$REPOS_FILE"
    # 清理嵌套 .git 以便源码提交到主仓库
    find "$SRC_DIR" -name ".git" -type d -prune -exec rm -rf {} + 2>/dev/null || true
}

# ─── 主流程 ───

parse_args "$@"
ensure_vcstool
mkdir -p "$SRC_DIR"

WANTED=$(get_wanted_repos)
remove_stale_repos "$WANTED"
import_repos

COUNT=$(echo "$WANTED" | wc -l)
echo "[OK] 已同步 $COUNT 个仓库到 src/$DISTRO"
echo "请 git add src/$DISTRO/ && git commit"
