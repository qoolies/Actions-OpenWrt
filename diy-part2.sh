#!/usr/bin/env bash
#
# File: diy-part2.sh
# Description: feeds install 之后、make defconfig 之前执行；工作目录 = openwrt/
#
# 这里做「改源码」类的小动作：默认 IP、主机名、默认主题…
# 每个动作都带存在性保护 —— 上游改了路径就打印 WARN 跳过，而不是静默失效。
#
set -euo pipefail

# ---------- 想改的值都放这里 ----------
LAN_IP="${LAN_IP:-192.168.0.2}"
ROUTER_HOSTNAME="${ROUTER_HOSTNAME:-MyRouter}"
# lede 默认 timezone='GMT0' / zonename='UTC'，北京时间对应下面这一对
ROUTER_TIMEZONE="${ROUTER_TIMEZONE:-CST-8}"
ROUTER_ZONENAME="${ROUTER_ZONENAME:-Asia/Shanghai}"

# replace_in_file <文件> <原文> <新文> <说明>
replace_in_file() {
    local f="$1" old="$2" new="$3" desc="$4"
    if [ ! -f "$f" ]; then
        echo "::warning::$f 不存在，跳过：$desc（上游可能改了路径，确认后再改）"
        return 0
    fi
    if ! grep -qF -- "$old" "$f"; then
        echo "::warning::$f 里找不到「$old」，跳过：$desc"
        return 0
    fi
    sed -i "s|${old}|${new}|g" "$f"
    echo "  ✔ $desc"
}

GEN=package/base-files/files/bin/config_generate

# ---------- 默认 LAN IP ----------
replace_in_file "$GEN" '192.168.1.1' "$LAN_IP" "默认 LAN IP → $LAN_IP"

# ---------- 默认主机名 ----------
# lede 用的是 LEDE，上游 openwrt 是 OpenWrt；两个都试，找不到只警告不中断
replace_in_file "$GEN" "hostname='LEDE'" "hostname='${ROUTER_HOSTNAME}'" "默认主机名 → $ROUTER_HOSTNAME"
replace_in_file "$GEN" "hostname='OpenWrt'" "hostname='${ROUTER_HOSTNAME}'" "默认主机名 → $ROUTER_HOSTNAME"

# ---------- 默认时区 ----------
replace_in_file "$GEN" "timezone='GMT0'" "timezone='${ROUTER_TIMEZONE}'" "默认时区 → $ROUTER_TIMEZONE"
replace_in_file "$GEN" "zonename='UTC'" "zonename='${ROUTER_ZONENAME}'" "默认时区名 → $ROUTER_ZONENAME"

# ---------- 其它常用动作（按需取消注释）----------
#
# 默认主题换成 argon（前提：config/packages.txt 里有 luci-theme-argon）
# replace_in_file feeds/luci/collections/luci/Makefile 'luci-theme-bootstrap' 'luci-theme-argon' "默认主题 → argon"
#
# 改默认 root 密码（默认是空的，只能靠首次登录设置；这个值要写 sha512 或明文）
# sed -i "s|^root:.*|root:\$1\$xxxx$(date +%s)yyyy\$/|" package/base-files/files/etc/shadow
#
# 精简固件体积：直接删掉不要的包目录（比在 .config 里关更快更干净）
# rm -rf feeds/luci/applications/luci-app-nlbwmon
# rm -rf feeds/luci/applications/luci-app-vlmcsd
#
# 打补丁：把 .patch 放进 patch/ 同名目录，然后在这里 apply
# patch -p1 < "$GITHUB_WORKSPACE/patches/01-foo.patch"

echo "=== diy-part2.sh 完成 ==="
