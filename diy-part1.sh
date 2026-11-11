#!/usr/bin/env bash
#
# File: diy-part1.sh
# Description: feeds update 之前执行；工作目录 = openwrt/
#
# 这里只做两件事：加 feed，或者把「非标准布局」的仓库摊平到 package/。
# 想装的包写进 config/packages.txt，不要在这里写 CONFIG_*。
#
set -euo pipefail

# ---------- 加 feed（重复执行安全，已存在则改 URL）----------
# 用法：add_feed <名字> <URL>[;分支]
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
# 用法：add_flat_feed <git 地址> <子目录>
add_flat_feed() {
    local url="$1" sub="$2" tmp
    tmp="$(mktemp -d)"
    git clone --depth=1 "$url" "$tmp/src" >/dev/null
    [ -d "$tmp/src/$sub" ] || { echo "::error::$url 里没有 $sub 目录"; rm -rf "$tmp"; return 1; }
    mkdir -p package
    cp -r "$tmp/src/$sub"/. package/
    rm -rf "$tmp"
    echo "  + 已摊平 ${url} 的 ${sub}/* → package/"
}

echo "=== diy-part1.sh：当前 feed 清单 ==="
grep -E '^[[:space:]]*src-' feeds.conf.default | sed 's/^/  /'

# ---------- 默认不启用的第三方 feed，按需取消注释 ----------
# 注意：取消注释后，还要把需要的包名写进 config/packages.txt。
#
# add_feed passwall https://github.com/xiaorouji/openwrt-passwall
# add_feed small    https://github.com/kenzok8/small
# add_feed mihomo   https://github.com/morytyann/OpenWrt-mihomo
#
# 想用 iStore 应用商店：打开下面这行，再在 config/packages.txt 里启用 luci-app-store
# add_flat_feed https://github.com/istoreos/istore.git luci
#
# 想固定某个包到自己的 fork（钉死版本、避免上游改动打断编译）：
# add_feed mine    https://github.com/qoolies/my-packages;main

echo "=== diy-part1.sh 完成 ==="
