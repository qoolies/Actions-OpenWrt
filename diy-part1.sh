#!/usr/bin/env bash
#
# File: diy-part1.sh
# Description: feeds update 之前执行；工作目录 = openwrt/
#
# 这里只做两件事：加 feed，或者把「非标准布局」的仓库摊平到 package/。
# 要加哪些 feed 写在 config/feeds.txt 里（不用改这个脚本）；
# 要装哪些包写在 config/packages.txt 里（不要在这里写 CONFIG_*）。
#
set -euo pipefail

ROOT_DIR="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
FEEDS_FILE="${FEEDS_FILE:-$ROOT_DIR/config/feeds.txt}"

# ---------- 加 feed（重复执行安全，已存在则改 URL）----------
add_feed() {
    local name="$1" url="$2"
    if grep -q "^src-git[[:space:]]\+${name}[[:space:]]" feeds.conf.default; then
        sed -i "s|^src-git[[:space:]]\+${name}[[:space:]].*|src-git ${name} ${url}|" feeds.conf.default
        echo "  ~ feed ${name} 已存在，改为 ${url}"
    else
        echo "src-git ${name} ${url}" >>feeds.conf.default
        echo "  + feed ${name} = ${url}"
    fi
}

# ---------- 摊平「包埋在子目录里」的仓库 ----------
# iStore 这类仓库不是标准 feed 布局（包在 luci/ 下），src-git 加不进去，
# 只能把子目录里的包目录搬到 package/ 下。
add_flat_feed() {
    local url="$1" sub="$2" tmp
    tmp="$(mktemp -d)"
    git clone --depth=1 "$url" "$tmp/src" >/dev/null
    if [ ! -d "$tmp/src/$sub" ]; then
        echo "::error::$url 里没有 $sub 目录（布局变了？用 git ls-tree 看一下再改）"
        rm -rf "$tmp"
        return 1
    fi
    mkdir -p package
    cp -r "$tmp/src/$sub"/. package/
    rm -rf "$tmp"
    echo "  + 已摊平 ${url} 的 ${sub}/* → package/"
}

echo "=== diy-part1.sh：当前 feed 清单 ==="
grep -E '^[[:space:]]*src-' feeds.conf.default | sed 's/^/  /'

# ---------- 读取 config/feeds.txt ----------
if [ -f "$FEEDS_FILE" ]; then
    echo "=== 追加 config/feeds.txt 里的 feed ==="
    set -f                                                              # 关掉通配符展开，URL 里的 * 才不会被 bash 吃掉
    while IFS= read -r raw || [ -n "$raw" ]; do
        line="${raw%%#*}"                                                   # 去注释
        line="$(printf '%s' "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        # shellcheck disable=SC2086
        set -- $line
        name="${1:-}"
        url="${2:-}"
        third="${3:-}"
        if [ -z "$name" ] || [ -z "$url" ]; then
            echo "::warning::config/feeds.txt 这一行缺名字或 URL，已跳过：$raw"
            continue
        fi
        case "$third" in
            flatten=*) add_flat_feed "$url" "${third#flatten=}" ;;
            "")        add_feed "$name" "$url" ;;
            *)         add_feed "$name" "$url;$third" ;;
        esac
    done <"$FEEDS_FILE"
else
    echo "（没有 config/feeds.txt，只用 lede 自带 feeds）"
fi

echo "=== diy-part1.sh：最终 feed 清单 ==="
grep -E '^[[:space:]]*src-' feeds.conf.default | sed 's/^/  /'
echo "=== diy-part1.sh 完成 ==="
