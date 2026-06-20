#!/usr/bin/env bash
# update_src.sh — 以 repos/<distro>*.repos 为唯一真相源，同步 ROS2 与 vendor 上游源码
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<EOF
用法: ./scripts/update_src.sh <distro>

从 repos/<distro>.repos 及 repos/<distro>-*.repos 同步全部源码到 src/<distro>/。
vendor 上游统一为 <pkg>/<name>_src/（含 *-cli.repos 中的 pybind11_src）。

参数:
  distro    humble 或 jazzy
EOF
}

parse_args() {
    DISTRO=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            humble|jazzy) DISTRO="$1"; shift ;;
            *) echo "错误: 未知参数 $1"; usage; exit 1 ;;
        esac
    done
    if [ -z "$DISTRO" ]; then
        echo "错误: 必须指定 distro (humble 或 jazzy)"
        usage
        exit 1
    fi
    SRC_DIR="$REPO_ROOT/src/$DISTRO"
}

ensure_vcstool() {
    command -v vcs &>/dev/null || pip3 install vcstool
}

# 解析所有 .repos 中的仓库路径（含 ros2/foo_vendor/bar_src 等嵌套路径）
get_wanted_repos() {
    local wanted="" f
    for f in "${REPOS_FILES[@]}"; do
        local entries
        entries=$(grep -E '^ {2}[a-zA-Z0-9_./-]+:$' "$f" | sed 's/^  //;s/:$//')
        wanted="${wanted:+$wanted$'\n'}$entries"
    done
    echo "$wanted"
}

remove_stale_repos() {
    local wanted=$1 org org_dir repo_dir path sub
    [ -d "$SRC_DIR" ] || return 0

    # 顶层 org/repo
    for org_dir in "$SRC_DIR"/*/; do
        [ -d "$org_dir" ] || continue
        org=$(basename "$org_dir")
        for repo_dir in "$org_dir"/*/; do
            [ -d "$repo_dir" ] || continue
            path="$org/$(basename "$repo_dir")"
            if ! echo "$wanted" | grep -qx "$path"; then
                echo "[INFO] 移除不在 .repos 中的仓库: $path"
                rm -rf "$repo_dir"
            fi
        done
        rmdir "$org_dir" 2>/dev/null || true
    done

    # vendor 上游（三级路径，目录名以 _src 结尾）
    local sub path
    while IFS= read -r -d '' sub; do
        path="${sub#$SRC_DIR/}"
        path="${path%/}"
        if ! echo "$wanted" | grep -qx "$path"; then
            echo "[INFO] 移除不在 .repos 中的 vendor 上游: $path"
            rm -rf "$sub"
        fi
    done < <(find "$SRC_DIR" -mindepth 3 -maxdepth 3 -type d -name '*_src' -print0 2>/dev/null)
}

# 删除空的 vendor 上游目录，避免 vcs import --skip-existing 跳过克隆
repair_empty_vendor_src() {
    local wanted=$1 path dest marker
    while IFS= read -r path; do
        is_vendor_upstream_path "$path" || continue
        dest="$SRC_DIR/$path"
        if [[ "$path" == *libyaml_src ]]; then
            marker=cmake/config.h.in
        else
            marker=CMakeLists.txt
        fi
        if [ -d "$dest" ] && [ ! -f "$dest/$marker" ]; then
            echo "[INFO] 移除空的 vendor 上游目录: $path"
            rm -rf "$dest"
        fi
    done <<< "$wanted"
}

import_repos() {
    local f label
    echo "[INFO] 同步 $DISTRO 源码 (${#REPOS_FILES[@]} 个 repos 文件)..."
    for f in "${REPOS_FILES[@]}"; do
        label=$(basename "$f" .repos | sed "s/^${DISTRO}//;s/^-*//")
        [ -z "$label" ] && label=core
        echo "  → $label"
        vcs import --skip-existing "$SRC_DIR" < "$f"
    done
}

postprocess_src() {
    # 嵌套 .git 清理，便于提交到主仓库
    find "$SRC_DIR" -name .git -type d -prune -exec rm -rf {} + 2>/dev/null || true
    # libyaml 上游 .gitignore 会误排除 cmake/config.h.in
    while IFS= read -r gi; do
        [ -f "$gi" ] && sed -i 's|!config/config.h.in|!cmake/config.h.in|' "$gi"
    done < <(find "$SRC_DIR" -path '*/libyaml_src/.gitignore' 2>/dev/null)
}

is_vendor_upstream_path() {
    [[ "$1" == */*_src ]]
}

verify_vendor_src() {
    local wanted=$1 path marker missing=0 n=0
    while IFS= read -r path; do
        is_vendor_upstream_path "$path" || continue
        n=$((n + 1))
        if [[ "$path" == *libyaml_src ]]; then
            marker=cmake/config.h.in
        else
            marker=CMakeLists.txt
        fi
        if [ ! -f "$SRC_DIR/$path/$marker" ]; then
            echo "[ERROR] 缺失 vendor 上游: src/$DISTRO/$path/$marker"
            missing=1
        fi
    done <<< "$wanted"
    [ "$missing" -eq 0 ] || exit 1
    echo "[OK] vendor 上游源码就绪 ($n 个)"
}

bump_version() {
	  local ver_file="$REPO_ROOT/VERSION"
	  local today="v$(date +%Y.%m)"

	  if [ -f "$ver_file" ]; then
	    local cur
	    cur=$(cat "$ver_file")
	    if [[ "$cur" == "$today"* ]]; then
	      # 同月: 递增 patch 号
	      local patch="${cur##*.}"
	      echo "${today}.$((patch + 1))" > "$ver_file"
	    else
	      echo "${today}.1" > "$ver_file"
	    fi
	  else
	    echo "${today}.1" > "$ver_file"
	  fi
	  echo "[INFO] VERSION: $(cat "$ver_file")"
	}

# ─── main ───
parse_args "$@"
ensure_vcstool
mkdir -p "$SRC_DIR"
bump_version

REPOS_FILES=("$REPO_ROOT/repos/${DISTRO}.repos")
for f in "$REPO_ROOT/repos/${DISTRO}"-*.repos; do
    [ -f "$f" ] && REPOS_FILES+=("$f")
done
[ -f "${REPOS_FILES[0]}" ] || { echo "错误: repos 文件不存在"; exit 1; }

WANTED=$(get_wanted_repos)
remove_stale_repos "$WANTED"
repair_empty_vendor_src "$WANTED"
import_repos
postprocess_src
verify_vendor_src "$WANTED"

COUNT=$(echo "$WANTED" | grep -c . || true)
echo "[OK] 已同步 $COUNT 个仓库到 src/$DISTRO"
echo "请 git add src/$DISTRO/ && git commit"
