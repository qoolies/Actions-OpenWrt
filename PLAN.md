# 下一版优化方案

基于 [#11 这次成功运行](https://github.com/qoolies/Actions-OpenWrt/actions/runs/42956700347)（2026-11-11 12:03 → 13:33 北京时间，全绿，产物 226 MB）的实测数据。

---

## 1. 先看这次跑成了什么样

| 步骤 | 耗时 | 判断 |
|---|---|---|
| Initialization environment（apt 装依赖） | 4m48s | 正常，换 runner 版本才会变 |
| Clone source code（`--depth 1`） | 7s | ✅ 比全量 clone 快一半 |
| Update / Install feeds | 1m00s | 正常 |
| 包存在性预检 | **< 1s** | ✅ 新增步骤，零成本 |
| make defconfig + 对账 | 26s | 正常 |
| Download packages | 3m41s | 正常（上游镜像快） |
| **Compile the firmware** | **79m21s** | ⚠️ **这是唯一值得动的地方** |
| 上传 artifact | 7s | ✅ |
| **总计** | **89m44s** | |

顺带确认：`Restore ccache` 用 0 秒、`actions/caches` 接口返回 `total_count: 0` —— **ccache 一个字节都没存下来**，这次是纯全量编译。原因见下。

---

## 2. 已修复（P0，本次已改进代码）

### 2.1 ccache 的路径被 lede 的 rules.mk 强制覆盖 —— 这是「配了但没用」的真凶

lede 的 `rules.mk` 里是无条件赋值再 export：

```make
ifneq ($(CONFIG_CCACHE),)
  TARGET_CC:= ccache $(TARGET_CC)
  ...
  export CCACHE_NOCOMPRESS:=true
  export CCACHE_BASEDIR:=$(TOPDIR)
  export CCACHE_DIR:=$(if $(call qstrip,$(CONFIG_CCACHE_DIR)),$(call qstrip,$(CONFIG_CCACHE_DIR)),$(TOPDIR)/.ccache)
endif
```

也就是说：我在 workflow 里设的 `CCACHE_DIR=/workdir/.ccache` **会被 make 覆盖成 `/workdir/openwrt/.ccache`**，
而缓存动作去收 `/workdir/.ccache` —— 那个目录根本不存在，于是「保存成功、内容为空」。

改法（已落地）：

- 缓存路径改成 `/workdir/openwrt/.ccache`，与 rules.mk 的默认值一致
- `env.CCACHE_DIR` 也指向同一处，这样 `ccache -s` 读到的是同一份统计
- 新增 **Report ccache stats** 步骤：把命中率、缓存体积写进 Summary。以后再「配了没生效」，Summary 里一眼能看出来
- ⚠️ 注意 `CCACHE_NOCOMPRESS:=true`：缓存是**不压缩**的，全量 x86 构建大约 3–5 GB，所以 `CCACHE_MAXSIZE` 设 3G（够用且不撑爆 GitHub 每仓库 10 GB 配额）

**预期收益**：第二次起，改两三个包的编译大约 30–45 分钟（相比 79 分钟）。

### 2.2 上传固件时别再压缩一遍

产物是 `.img.gz`，`upload-artifact` 默认还会 zip 压缩，白烧 1–2 分钟 CPU。
已加 `compression-level: 0`，并加 `if-no-files-found: error`（固件没产出来就直接报错，不要静默）。

### 2.3 timeout 从 350 分钟收到 240

实测 90 分钟，350 分钟只会在卡死时白烧额度。

### 2.4 「加源」这件事变成一行配置

新增 `config/feeds.txt`，`diy-part1.sh` 自动读取：

```text
passwall  https://github.com/xiaorouji/openwrt-passwall
istore    https://github.com/istoreos/istore.git flatten=luci
```

- 第三列 `flatten=xxx`：非标准布局的仓库（iStore），把 `xxx/` 下的包摊平到 `package/`
- 第三列写别的：当分支用（等价 `;分支`）
- 重复执行安全（同名 feed 只更新 URL，不会写两遍）
- 关掉了通配符展开，URL 里带 `*` 也不会被 bash 吃掉

### 2.5 预检现在会告诉你「下一步怎么做」

包找不到时，除了列出名字，还会给近似名（用于判断是拼错还是在别的 feed 里），并直接给出三条处理路径。

---

## 3. 「包找不到 → 加个源」到底管不管用？

**大部分情况管用，但要先分清三种原因**，否则加了源照样找不到：

| 现象 | 原因 | 正确做法 |
|---|---|---|
| 包名在源码树里完全没有，但网上确实有 | 该包在**别的仓库**里 | `config/feeds.txt` 加一行 feed，再在 `packages.txt` 写包名 |
| 包名在源码树里完全没有，且换了几个源都没有 | 名字写错（如 `luci-app-adguard-home` ≠ `luci-app-adguardhome`） | 看预检给的「近似名」改拼写 |
| 包名以前有、现在没有 | 上游在**当前分支**移除了（如 `luci-app-turboacc` 在 luci@25.12 被移除） | 要么放弃，要么把整个 luci feed 降到 24.10（**不推荐**，版本错配的坑更大） |
| 包名在树里，但没进固件 | 依赖不满足，被 defconfig 丢弃 | 看 post 阶段对账；通常是缺 kmod 或依赖包 |

**加 feed 的三个注意点：**

1. **布局必须是标准的**（`包名/Makefile` 直接在仓库根，或 `applications/` 这类一层子目录）。
   像 iStore 这种包埋在 `luci/` 下的，`src-git` 加不进去，只能 `flatten=`。
2. **会不会打架**：`kenzok8/small` 这类大杂烩 feed 里有大量与 lede 同名的 `luci-app-*`，
   feed 顺序靠后的会覆盖靠前的 —— 表现是「包能编，但界面变成另一家的」。不确定就别加。
3. **版本要匹配**：lede 的 luci 现在锁在 `openwrt-25.12`，从 24.10 抄来的包可能依赖不存在的东西。

**推荐的最小做法**：只在你确实要某个包时加**那一个** feed，加完跑一次，看 Summary 里预检是不是变绿，再决定要不要继续。

### 3.1 「默认源优先、没有的再去新源里找」—— 已经成立（已核对源码）

`scripts/feeds` 的 `install -a` 逻辑是：

```perl
foreach my $f (@feeds) {                    # @feeds 就是 feeds.conf 的顺序
    get_feed($f->[1]);
    foreach my $name (sort keys %$feed_src) {
        install_src($feed, $name, ...);     # lookup_src 从 @feeds 里取第一个命中的
```

`install_src` 里还有两道闸：

```perl
my $select_feed = lookup_src($feed, $name);  # 第一个提供它的 feed
...
if ($installed{$name}) { return 0 if ($installed{$name} == 1); }   # 装过就跳过
```

所以：

1. **同一个包名，只有 feeds.conf 里排最前的那份会被装进来**，后面的直接跳过，不会双份定义；
2. **核心包（`package/` 下的）优先级高于所有 feed**，除非 `-f` 强行覆盖；
3. 我们的额外 feed 是**追加在末尾**的，因此「默认源优先、没有才用新源」是**现有行为的自然结果**，
   不需要写任何仲裁代码。

真正需要补的是**可见性**：以前「加了源但没生效」是静默的。现在预检会输出：

```
| 包 | 来源 |
| luci-app-openclash | luci small |     ← 两个源都有，最终用 luci
| luci-app-passwall  | small      |     ← 只有新源有，正常
```

并在多源时给 `::notice::`。反过来「我想让外部源的版本生效」也有明确写法（`feeds uninstall` + `install -p`），
见 README「强制用外部源的版本」。

---

## 4. 还可以做但这次没做的（P1，按性价比排序）

| 项 | 收益 | 成本 / 风险 | 建议 |
|---|---|---|---|
| **缓存 `dl/`（源码包下载）** | 省 ~3.5 分钟/次 | 约 1.5–2 GB 配额，会和 ccache 抢 10 GB 预算 | 先观察 ccache 体积：若 < 5 GB，再加 dl 缓存 |
| **改配置后自动触发**（`on.push.paths: config/**`） | 不用手动点 | 会消耗 Actions 额度；改注释也会触发 | 想要"提交即编译"再开 |
| **`STRICT` 默认 true** | 缺包直接失败，杜绝"绿勾缺插件" | 上游一改包名就红，得手动修 | 等你熟悉这套流程后再开 |
| **多机型 matrix**（x86 + arm64 一次编两个） | 一仓多用的确方便 | 单次 3 小时、占满并发额度 | 只有真有两台设备才值得 |
| **`make -j$(nproc+1)`** | 理论上快 5% 左右 | 4 vCPU 上可能反而更慢 | 实测后再决定，别拍脑袋 |
| **自建 runner / 用 ophub 的 docker 镜像** | 编译环境稳定、省 apt 4 分钟 | 要一台常开的机器 | 有闲置服务器再考虑 |

---

## 5. 日常维护建议

1. **改配置**：只改 `config/packages.txt`（插件）和 `config/feeds.txt`（源），改完跑一次看 Summary。
2. **锁定版本**：lede master 天天变。想稳定，就把 `DEFAULT_BRANCH` 改成某个 commit/tag，
   每季度手动升级一次；否则接受"偶发红叉，重跑一次"。
3. **看三个数**：Summary 里的「找不到的包数」「ccache 命中率」「总耗时」。第一个非 0 就去改配置，
   第二个长期为 0 说明缓存没接上，第三个突然翻倍说明上游某个包开始拖后腿。
4. **失败了别急着重跑**：先看「失败定位」里摘出的包名，`!包名` 写进 `packages.txt` 先出一版可用固件。
