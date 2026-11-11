#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# 工作目录同样是 openwrt/ ，且此时 feeds 已经 update + install 完毕

# ---------- 修改默认 LAN IP（192.168.1.1 -> 192.168.0.2） ----------
GEN=package/base-files/files/bin/config_generate
if [ -f "$GEN" ]; then
    sed -i 's/192\.168\.1\.1/192.168.0.2/g' "$GEN"
else
    echo "WARN: $GEN 不存在，跳过改 IP（上游可能换了路径，确认后再改）"
fi

# ---------- 修改主机名 ----------
# sed -i 's/OpenWrt/MyRouter/g' package/base-files/files/bin/config_generate

# ---------- 修改默认主题（Argon） ----------
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# ---------- 精简固件体积（可选） ----------
# rm -rf feeds/luci/applications/luci-app-nlbwmon
# rm -rf feeds/packages/net/mosquitto
