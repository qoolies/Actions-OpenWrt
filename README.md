# Actions-OpenWrt · 个人云编译仓库

用 GitHub Actions 编译 **coolsnowwolf/lede** 固件，默认目标是 **x86_64 generic**（PVE 虚拟机 / 软路由）。
日常只需要改 `config/packages.txt` 这一个文件。

首次构建约 1h50m；开启 ccache 后，第二次起通常 40–70 分钟。

---

## 1. 只改这几个地方

| 路径 | 作用 | 什么时候改 |
|---|---|---|
| `config/packages.txt` | 插件清单，一行一个包名，`!` 开头 = 显式关闭 | **加 / 删插件（90% 的改动）** |
| `config/base.config` | 机型、分区大小、镜像格式、ccache | 换设备、改磁盘大小 |
| `config/extra.config` | 其它零散 `CONFIG_*`（默认全注释 = 不改） | 关 IPv6、换主题、砍体积 |
| `diy-part1.sh` | feeds update **之前**：加 feed、摊平 iStore | 要装第三方源里的包 |
| `diy-part2.sh` | feeds install **之后**：默认 IP / 主机名 / 时区 | 改固件出厂默认值 |
| `scripts/gen-config.sh` | 把上面三份配置拼成 `openwrt/.config` | 一般不用动 |
| `scripts/check-packages.sh` | 编译前预检 + defconfig 后对账 | 一般不用动 |
| `.github/workflows/openwrt-builder.yml` | 流水线本体 | 一般不用动 |

`openwrt/.config` **不再入库**：它由 `scripts/gen-config.sh` 在 CI 里现场生成，
仓库里那三份配置才是唯一真相，不存在「改错了文件」这种事。

> 上一版仓库的体检报告在 [REVIEW.md](REVIEW.md)，这一版改了什么、和别的仓库比差在哪，见 [UPGRADE.md](UPGRADE.md)。

---

## 2. 怎么跑

**Actions → OpenWrt Builder → Run workflow。**

运行参数（不改文件也能改行为）：

| 输入 | 说明 |
|---|---|
| `source_repo` | 换源码仓库，留空 = lede |
| `source_branch` | 分支或 tag，留空 = master。填 tag 可锁定上游版本 |
| `extra_packages` | 本次临时加包，空格分隔，如 `luci-app-ttyd !luci-app-wol` |
| `release` | 构建成功后发 Release（默认否） |
| `use_ccache` | 使用 ccache（默认是） |
| `debug_ssh` | 失败时开 tmate SSH 进运行环境（默认否，会挂起 30 分钟） |

想让它每 3 天自动跟着上游编译：打开 `.github/workflows/update-checker.yml` 里的 `schedule` 注释。

---

## 3. 每次跑完，看 Summary 而不是只看红绿

运行页面的 **Summary** 从上到下依次是：

1. **本次构建参数** —— 源码/分支/临时加包/ccache 是否开启
2. **配置生成** —— 启用几个包、关掉几个包
3. **包存在性预检** —— ⚠️ 这是新增的关键一步：**编译前 5 秒**告诉你哪些包在 feed 里根本不存在（包名写错、feed 没加、分支已移除）。这种包不会让编译失败，只会「绿勾但固件里没有」
4. **make defconfig 警告 + 配置解析对账** —— 源码里有、但 `defconfig` 没选中的包（通常是依赖不满足）
5. **镜像产物 + 对账** —— 逐个检查你请求的包是否真的出现在 `bin/targets` 的包清单里（`bin/packages` 只是编译产物，不代表被装进镜像）

失败时会额外出现 **失败定位** 块：摘录最后的报错行和涉及的包目录，并直接给出处理建议。

---

## 4. 常用配方

### 加一个插件

```text
# config/packages.txt
luci-app-diskman
```

前提是该包在某个已启用的 feed 里（lede 默认有 packages / luci / routing / telephony / helloworld / video）。
包名不知道？看 `feeds/luci/applications/` 下的目录名，或直接跑一次，预检会告诉你有没有。

### 删掉一个默认插件

lede 的 `DEFAULT_PACKAGES.router` 默认会编进十几个 luci 应用（ddns、upnp、autoreboot、nlbwmon、turboacc…）。
想关掉就在 `packages.txt` 里加一行 `!包名`：

```text
!luci-app-ssr-plus
!luci-app-nlbwmon
```

### 换机型

改 `config/base.config` 顶部三行（目标平台那一段），例如 ARM 软路由：

```text
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_r2s=y
```

机型符号不熟时，在本地 `make menuconfig` 选好后 `grep '^CONFIG_TARGET' .config` 抄过来即可。

### 改 LAN IP / 主机名 / 时区

`diy-part2.sh` 顶部三个变量：

```sh
LAN_IP="${LAN_IP:-192.168.0.2}"
ROUTER_HOSTNAME="${ROUTER_HOSTNAME:-MyRouter}"
ROUTER_TIMEZONE="${ROUTER_TIMEZONE:-CST-8}"
```

这些是「出厂默认值」，刷机后仍然可以在 LuCI 里改。
上游换路径或换写法时脚本会打印 `::warning::` 跳过，不会静默失效。

### 加第三方 feed

`diy-part1.sh` 里取消注释一行即可：

```sh
add_feed passwall https://github.com/xiaorouji/openwrt-passwall
```

重复执行安全（已存在就改 URL）。加完记得把包名写进 `config/packages.txt`。

### 装 iStore 应用商店

iStore 的仓库不是标准 feed 布局（包埋在 `luci/` 子目录），要「摊平」：

```sh
# diy-part1.sh
add_flat_feed https://github.com/istoreos/istore.git luci
```

然后 `config/packages.txt` 里启用 `luci-app-store`。

### 砍体积

- 小的：`config/extra.config` 里关掉用不上的默认包（vsftpd / vlmcsd / nlbwmon / wol …）
- 大的：`diy-part2.sh` 里直接 `rm -rf` 掉整个包目录（比在 .config 里关更快、不会有残留依赖）
- 更彻底：`config/base.config` 里把 `CONFIG_TARGET_ROOTFS_PARTSIZE` 从 2048 降到 1024

### 锁定上游版本（防「今天能过明天过不了」）

lede master 每天在变。要稳定就钉版本：

- 懒人版：`source_branch` 输入框填一个 tag
- 彻底版：把 `.github/workflows/openwrt-builder.yml` 里 `DEFAULT_BRANCH` 改成某个 commit 或 tag

### 发布 Release

运行时把 `release` 勾上。产物会进一条 release，正文自动写好上游 commit、插件清单、镜像大小；
旧 release 自动保留最近 3 个（`KEEP_RELEASES`）。

### 编译失败怎么办

1. 看 Summary 的 **失败定位**：里面已经摘出了报错行和包目录
2. 九成情况是**上游某个包自己编不过**，和你的配置无关。把它的名字写进 `packages.txt` 并加 `!` 前缀，重跑即可出固件
3. 下载 artifact `build-logs*`，里面有完整 `build.log`、`defconfig.log` 和最终 `.config`
4. 想进容器手动查：勾 `debug_ssh` 重跑，失败后会输出 SSH 地址（默认挂 30 分钟）

---

## 5. 冷知识（踩过的坑）

- **`.config` 的 `=y` 行可以带行尾注释**（Kconfig 只看第一个字符），但**数字/字符串行不行**（整串校验，会被判非法丢弃）。所以本仓库把说明都单独写成一行。
- **`make defconfig` 遇到不认识的 `CONFIG_` 符号不报错，直接跳过**，这就是「绿勾但没插件」的根源 —— 预检步骤专治这个。
- **`feeds.conf.default` 写错会在 `Update feeds` 一秒内失败**。格式是 `src-git <名字> <URL>[;<分支>]`。
- **`bin/packages` 不等于装了包**：那只是编译出来的 ipk/apk；判断有没有进固件只看 `bin/targets` 下的清单。
- **lede 默认主机名是 `LEDE`，不是 `OpenWrt`**，默认时区是 `GMT0`/`UTC`。
- 当前 lede 的 luci feed 锁在 **openwrt-25.12** 分支：`luci-app-turboacc`、`luci-app-accesscontrol` 在该分支已被移除，写了也只会进「找不到」报告。
