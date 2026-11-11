# Actions-OpenWrt 仓库体检报告

- 仓库：`qoolies/Actions-OpenWrt`（fork 自 P3TERX/Actions-OpenWrt）
- 默认分支：`main`，当前 HEAD：`6246cb1`（Update diy-part1.sh，2026-11-09）
- 编译源：`coolsnowwolf/lede@master`（现为 OpenWrt 25.12 线，内核配置含 6.12 / 6.18 / 7.3）
- 检查时间：2026-11-10

---

## 1. 结论：能跑，而且已经跑通过了

你的仓库最近一次运行是**成功的**，所以"能不能在 GitHub Actions 上编译"这个问题答案是肯定的：

| 运行 | 时间 | 结果 | 说明 |
|---|---|---|---|
| [#5](https://github.com/qoolies/Actions-OpenWrt/actions/runs/42567793790) | 11-09 13:31 → 15:23（北京） | ✅ success | 全 20 个 step 绿，产出 artifact `OpenWrt_firmware_generic_202611091523`，242 MB |
| [#4](https://github.com/qoolies/Actions-OpenWrt/actions/runs/42566895094) | 11-09 13:22 | ❌ failure | 卡在 `Update feeds`，1 秒就挂 → 当时 `diy-part1.sh` 里的 feed 写法有语法/URL 问题；随后改成模板默认内容就过了 |
| #3 | 11-09 13:13 | ❌ failure | 同类问题，早于 #4 |

各阶段耗时（#5）：环境初始化 4 min → clone 17 s → feeds 1 min → 下载 4 min → **编译 1 h 43 min**，总 1 h 52 min。距离 6 小时上限、磁盘上限都还有余量，说明当前这个"精简 .config"的规模是对的。

**但"绿勾"不等于"你要的插件都进去了"** —— 见第 3 节，这是本次检查最重要的部分。

---

## 2. 逐文件检查

### 2.1 `.config` —— 先说一个更正：`=y` 行的行尾注释其实无害

> ⚠️ **本节是更正版。** 我最初的判断（"行尾注释会让选项被丢弃"）是错的，后来直接读 `scripts/config/confdata.c` 源码确认了：`=y/m/n` 这种布尔/三态行，解析器**只看第一个字符**。

```c
/* openwrt/openwrt: scripts/config/confdata.c, conf_set_sym_val() */
case S_TRISTATE:
        if (p[0] == 'm') { sym->def[def].tri = mod; break; }
        /* fall through */
case S_BOOLEAN:
        if (p[0] == 'y') { sym->def[def].tri = yes; break; }   /* ← 只看 p[0] */
        if (p[0] == 'n') { sym->def[def].tri = no;  break; }
        conf_warning("symbol value '%s' invalid for %s", p, sym->name);
```

所以 `CONFIG_PACKAGE_luci-app-store=y          # iStore 应用商店` 完全合法，`y` 之后的文字被直接忽略——**你原来那份 `.config` 并没有因为注释而丢包**。

**但有两条例外，这两类是走严格路径的：**

```c
case S_INT:
case S_HEX:
        if (sym_string_valid(sym, p)) { ... }              /* 整串校验 */
        else conf_warning("symbol value '%s' invalid for %s", p, sym->name);
/* S_STRING 也是整串解析，会被当成 引号字符串 处理 */
```

也就是说 `CONFIG_TARGET_ROOTFS_PARTSIZE=2048   # 2G` 这种**数字/字符串行**加行尾注释才会被判定非法并丢弃。你原配置里只有插件行带了注释（都是 `=y`），数字行没带，所以从头到尾没受伤。

**结论修订：去掉行尾注释只是"卫生习惯"，不是必须的修复。** 我仍然建议去掉（避免以后在 `PARTSIZE` 这类行上踩坑），但它不是我上一轮说的 P0 问题。

**真正的问题 B：`.config` 首行还留着模板的占位注释**

**问题 B：`.config` 首行还留着模板的占位注释**

```
# This is an empty file, please overwrite it after generating the .config file with the source code
```

无害，但会让人以为这个文件没被用上，删掉更清楚。

**核对无误的部分：**

| 配置 | 结论 |
|---|---|
| `CONFIG_TARGET_x86` / `CONFIG_TARGET_x86_64` / `..._DEVICE_generic` | ✅ 正确。lede 的 [`target/linux/x86/64/target.mk`](https://github.com/coolsnowwolf/lede/blob/master/target/linux/x86/64/target.mk) 里 `ARCH:=x86_64`、`BOARDNAME:=x86_64`，profile 就叫 `generic`（小写 g，不能写成 `Generic`） |
| `CONFIG_TARGET_IMAGES_GZIP=y` | ✅ OpenWrt 通用符号，x86 上默认就是 y；产物是 `openwrt-x86-64-generic-squashfs-combined-efi.img.gz` |
| `CONFIG_TARGET_ROOTFS_PARTSIZE=2048` | ✅ 合法；配合 gzip 后单镜像约 200 MB 量级 |
| `kmod-igc` / `kmod-e1000e` / `kmod-virtio-net` | ✅ 均在 lede 内核模块里存在（i225/i226、Intel 千兆、PVE VirtIO） |
| 没写 `CONFIG_ALL` / `CONFIG_TARGET_ALL_PROFILES` | ✅ 好事，写了会顶到 6 小时/磁盘上限 |

一个可选的小优化：加 `CONFIG_TARGET_KERNEL_PARTSIZE=32`。默认 16 MB 在 6.12+ 内核上有点紧，改成 32 MB 更稳（我在修正版里已经加了）。

### 2.2 `.github/workflows/openwrt-builder.yml` —— 逻辑没问题，缺"可观测性"

这是 P3TERX 模板原封不动的一份，流程正确：`clone → feeds → mv .config → make defconfig → make download → make -j$(nproc) → 打包 artifact`。检查结论：

- ✅ `on: repository_dispatch` + `workflow_dispatch`：手动可触发，不需要 push
- ✅ `UPLOAD_FIRMWARE: true` + `UPLOAD_BIN_DIR: false`：只传 `bin/targets/x86/64/`，不会把整个 bin 传上去
- ✅ `Delete workflow runs` 在 #5 里是绿的，说明你仓库的 token 默认权限够用（不需要额外 `permissions`，但加上更保险）
- ⚠️ `make defconfig` 和真正的编译挤在同一步里，`defconfig` 的 warning 混在几千行日志里，等于隐形的
- ⚠️ 编译失败时不上传日志，`.config` 也被覆盖掉，排查只能靠翻 1.7 小时的日志
- ⚠️ `actions/upload-artifact@main` 不锁版本，哪天 main 变了行为会莫名其妙

### 2.3 `diy-part1.sh` —— 现在是空壳（这反而是它能跑通的原因）

当前内容全是注释，所以用的是 lede 自带的 [`feeds.conf.default`](https://github.com/coolsnowwolf/lede/blob/master/feeds.conf.default)：

```
src-git packages https://github.com/coolsnowwolf/packages.git
src-git luci     https://github.com/coolsnowwolf/luci.git;openwrt-25.12
src-git routing  ...
src-git telephony ...
src-git helloworld ...
src-git video ...
```

注意 `luci` 现在锁在 **openwrt-25.12** 分支上——这一点直接决定了第 3 节里几个包在不在。

### 2.4 `diy-part2.sh` —— 一行 sed，可用但要加保护

```sh
sed -i 's/192.168.1.1/192.168.0.2/g' package/base-files/files/bin/config_generate
```

- ✅ 路径在当前 lede 里是对的，改完默认 LAN 就是 192.168.0.2
- ⚠️ 这行 `sed` 没有 `[ -f ]` 保护：哪天上游挪了文件，脚本静默失败（不会报错，因为 `sed` 找不到文件才报错；`-i` 对不存在文件会报 "No such file"，但该步 `run` 没有 `set -e` 也不会中断，具体表现是改 IP 没生效）
- ⚠️ 把 `192.168.1.1` 全量替换成 `192.168.0.2` 会连带改掉 DHCP 段落的注释文本，无害但不好读

### 2.5 `update-checker.yml` —— 这个 workflow 现在跑会红

- ❌ `actions/cache@v3`：v3 已进入弃用期（官方 sunset），手动点一次大概率直接报错
- ❌ 没有 `permissions`，而它要 `repository-dispatch` + 删旧运行
- ✅ `schedule` 是注释掉的，所以不会每天自己跑——不影响你编译

---

## 3. 最关键的问题：8 个插件里有 3 个在默认 feed 里根本不存在

我把每个 `CONFIG_PACKAGE_xxx` 都拿到当前 feed 里对了一遍（`luci` = openwrt-25.12 分支，`packages` = master）：

| 请求的包 | 实际位置 | 结论 |
|---|---|---|
| `luci-app-adguardhome` | [luci/applications/luci-app-adguardhome](https://github.com/coolsnowwolf/luci/tree/openwrt-25.12/applications/luci-app-adguardhome) | ✅ 存在（依赖 `adguardhome`，[packages/net/adguardhome](https://github.com/coolsnowwolf/packages/tree/master/net/adguardhome) 也在，v0.107.79） |
| `luci-app-openclash` | [luci/applications/luci-app-openclash](https://github.com/coolsnowwolf/luci/tree/openwrt-25.12/applications/luci-app-openclash) | ✅ 存在（v0.48.002） |
| `luci-app-diskman` | [luci/applications/luci-app-diskman](https://github.com/coolsnowwolf/luci/tree/openwrt-25.12/applications/luci-app-diskman) | ✅ 存在 |
| `luci-theme-argon` | [luci/themes/luci-theme-argon](https://github.com/coolsnowwolf/luci/tree/openwrt-25.12/themes/luci-theme-argon) | ✅ 存在（v2.4.3） |
| `luci-app-ttyd` | luci feed | ✅ 存在 |
| `luci-app-store`（iStore） | **不在任何 lede feed 里**；官方仓库 [istoreos/istore/luci/luci-app-store](https://github.com/istoreos/istore/tree/main/luci) | ❌ 拿不到 → 静默丢弃 |
| `luci-app-turboacc` | [24.10 分支有](https://github.com/coolsnowwolf/luci/tree/openwrt-24.10/applications/luci-app-turboacc)，**25.12 分支已移除** | ❌ 拿不到 → 静默丢弃 |
| `luci-app-tailscale` | luci feed 里没有这个名字；只有本体 [packages/net/tailscale](https://github.com/coolsnowwolf/packages/tree/master/net/tailscale)（v1.84.2） | ❌ LuCI 界面拿不到；本体能编 |

也就是说：**你那次成功构建出来的固件里，没有 iStore、没有 TurboACC、没有 Tailscale 界面**——原因就是这三个符号在 feed 里不存在，`make defconfig` 遇到不认识的 `CONFIG_` 符号会直接跳过（`sym_find()` 返回 NULL → `continue`，默认连警告都不打）。

### 怎么补

1. **iStore**：官方仓库不是标准 feed 布局（包埋在 `luci/` 子目录），所以 `src-git` 加不进去，要在 `diy-part1.sh` 里摊平到 `package/`：

   ```sh
   git clone --depth=1 https://github.com/istoreos/istore.git istore-src
   mv istore-src/luci/* package/
   rm -rf istore-src
   ```

   然后 `.config` 里的 `CONFIG_PACKAGE_luci-app-store=y` 才会生效（`taskd`、`luci-lib-taskd`、`luci-lib-xterm` 会一起带进来）。

2. **TurboACC**：25.12 分支上限里没有了（多半跟 6.12+ 内核的加速补丁被丢弃有关）。别把整个 luci feed 降回 24.10 去兼容，版本错配的坑比少一个插件大。建议先不用，或等上游补回。

3. **Tailscale**：`.config` 里保留 `CONFIG_PACKAGE_tailscale=y`（本体能编），界面用 `tailscale up` 命令行配；想要 LuCI 页面，就得自己把 `luci-app-tailscale` 放进 feed。

---

## 4. 修正版文件（直接覆盖即可）

| 文件 | 改了什么 |
|---|---|
| [`.config`](.config) | 去掉全部行尾注释（卫生习惯，非必须）；补 `CONFIG_TARGET_ROOTFS_SQUASHFS` / `CONFIG_TARGET_KERNEL_PARTSIZE=32`；三个 feed 里拿不到的包改成行首注释的"待开启"块；`adguardhome` / `tailscale` 本体显式写上 |
| [`.github/workflows/openwrt-builder.yml`](.github/workflows/openwrt-builder.yml) | `make defconfig` 拆成独立步骤，把「请求的选项 vs 实际生效」写进 run summary；新增「镜像产物 + 插件是否真的编入」报告；失败时上传 `.config` 和 `logs/`；artifact 动作锁 v4；加 `permissions` |
| [`diy-part1.sh`](diy-part1.sh) | 加上 iStore 的摊平装法（注释状态，按需打开）；说明当前 lede 默认 feed 有哪些 |
| [`diy-part2.sh`](diy-part2.sh) | 改 IP 那行加 `[ -f ]` 保护，路径不对时打印 WARN 而不是默默失败 |
| [`.github/workflows/update-checker.yml`](.github/workflows/update-checker.yml) | `actions/cache` v3 → v4、`repository-dispatch` v2 → v3、补 `permissions` |

加了「配置解析报告」之后，每次运行的 Summary 页面会直接告诉你：

```
### 配置解析报告
- 请求的选项：17 个
- 被 make defconfig 丢弃的选项（包不存在 / 依赖不满足 / 该行写法非法）：
  - PACKAGE_luci-app-turboacc
```

这是唯一能提前发现"绿勾但缺包"的办法。想让它直接失败而不是黄字警告，把 workflow 里的 `FAIL_ON_MISSING_PACKAGE: false` 改成 `true`。

---

## 5. 落地步骤

```bash
# 1. 把上面 5 个文件覆盖到你的 fork 里
git add -A && git commit -m "fix: .config 清理 + 加配置校验步骤"
git push origin main

# 2. 到 Actions → OpenWrt Builder → Run workflow（选 main）
#    约 1h50m 后看产物
```

产物验证（Download artifact 后解压）：

```
openwrt-x86-64-generic-squashfs-combined-efi.img.gz   ← PVE 用这个
openwrt-x86-64-generic-ext4-combined-efi.img.gz
```

PVE 导入：`gunzip` 后 `qm importdisk <vmid> openwrt-...img local-lvm`，引导选 UEFI。

固件起来后确认插件真的在：

```sh
# 25.12 线大概率是 apk，老版本是 opkg
apk info | grep -E 'luci-app|adguard|tailscale' || opkg list-installed | grep -E 'luci-app|adguard|tailscale'
```

---

## 6. 另外三点值得知道

1. **lede master 每天都在变**，你今天能过、明天可能过不了（内核配置里已经有 6.12/6.18/7.3 三份并存）。想稳定，把 `REPO_BRANCH` 固定到某个 tag/commit，或者接受"偶发红叉重跑一次"。
2. **失败最常见的原因不是你的配置**，而是上游某个包编不过。日志里搜 `Error 1` 定位到 `package/feeds/...` 后，临时把那个包关了就能出固件。
3. **改 `feeds.conf.default` 出错会在 `Update feeds` 一秒内失败**（#4 就是这样）。看到"1 秒挂"，先怀疑 feed 行：格式是 `src-git <名字> <URL>[;<分支>]`，别写 `src-git=<名字>`。
