#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
#echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
#echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default
# 1. 添加 iStore 应用商店源
echo 'src-git istore https://github.com/linkease/istore.git;main' >> feeds.conf.default

# 2. 添加 sbwml 的软件包源（用于最新 turboacc / tailscale 等）
echo 'src-git sbwml https://github.com/sbwml/openwrt-packages.git' >> feeds.conf.default

# 3. 添加 kiddin9 的综合软件包源（补充各种常用网卡驱动和 LuCI 插件）
echo 'src-git kiddin9 https://github.com/kiddin9/openwrt-packages.git' >> feeds.conf.default
