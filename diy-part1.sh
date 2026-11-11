#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# ---------- 追加 feed（如果需要） ----------
# 本脚本执行时的工作目录是 openwrt/，所以相对路径都相对源码根目录。
# lede 默认 feeds.conf.default 已经启用：packages / luci(openwrt-25.12)
# / routing / telephony / helloworld / video
#
# echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default
# echo 'src-git small https://github.com/kenzok8/small' >>feeds.conf.default

# ---------- 可选：补上 iStore 应用商店 ----------
# 官方仓库 istoreos/istore 不是标准 feed 布局（包在 luci/ 子目录下），
# 所以直接加 src-git 是不行的，要把 luci/ 下的包目录摊平到 package/ 里。
# 打开后 .config 里的 CONFIG_PACKAGE_luci-app-store=y 才会真正生效。
#
# git clone --depth=1 https://github.com/istoreos/istore.git istore-src
# mv istore-src/luci/* package/
# rm -rf istore-src
