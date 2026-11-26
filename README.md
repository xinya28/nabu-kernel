# nabu 内核构建（小米平板 5 / HyperOS 3 移植版）

在 GitHub Actions 上编译 **小米平板 5（nabu，SM8150-AC / 骁龙 860）** 的 **4.14.180-perf** 内核，
集成 **KernelSU 系 root（BakaSU + SUSFS）** 与一组**纯配置层**性能调优，产物是可直接刷入的
**AnyKernel3 zip** 和原始 `Image`。

---

## 1. 为什么是 4.14.180，而不是 4.19

对 `nabu_XiaomiPad5_OS3.0.304.0.WNSCNXM_16.0` 这个 ROM 包做过实测：

| 检查项 | 实测结果 |
| --- | --- |
| `boot.img` 头部 | header v3，内核位于 page 1，内核为**未压缩的 arm64 `Image`**（`ARMd` magic @0x38） |
| `boot.img` 内核版本串 | `Linux version 4.14.180-moon-os3-ga5805c039`（moon clang 20.0.0，2026-04-03） |
| `super.img` 内 `/vendor/lib/modules/*_dlkm.ko` | `vermagic=4.14.180-perf-gde52a0344e18 SMP preempt mod_unload modversions aarch64` |
| ROM 中是否存在 4.19 模块 | 否（全盘只有 4.14.180 一种 vermagic） |

也就是说：**这个 ROM 的闭源 vendor 模块只认 4.14.180**。换成 4.19 内核后
`adsp_dlkm`、`wcd_dlkm`、`cs35l41_dlkm`、`audio_dlkm`、`machine_dlkm`、`q6_dlkm`
等一整套 audio/DSP/HDMI 模块无法 `init_module`，直接后果是**开机卡小米 logo 或无声、无 wifi、相机全挂**。
要做到“4.19 + 系统功能正常”，必须连整个 vendor（7 GB 闭源 blob）一起重做，这已不是“换个内核”的量级。

### 那 “perf” 怎么办

`vermagic` 的比对逻辑在 `kernel/module.c` 的 `same_magic()`：

```c
static inline int same_magic(const char *amagic, const char *bmagic, bool has_crcs)
{
        if (has_crcs) {                       /* CONFIG_MODVERSIONS=y 时 */
                amagic += strcspn(amagic, " ");   /* 跳过版本号，只比对 "SMP preempt ..." */
                bmagic += strcspn(bmagic, " ");
        }
        return strcmp(amagic, bmagic) == 0;
}
```

因为本 ROM 的模块带 CRC（`modversions`），所以内核 release 串可以是
`4.14.180-perf`、`4.14.180-bpf-os3-bks` 或任何自定义后缀，**只要
`CONFIG_SMP / CONFIG_PREEMPT / CONFIG_MODULE_UNLOAD / CONFIG_MODVERSIONS` 与之匹配、
且导出符号的 CRC 一致**，vendor 模块就照常加载。CRC 由 `genksyms` 从头文件签名算出，
同一 4.14.180 基线 + 同一份 defconfig 即可保持一致（本流水线构建时会在日志里打印这几项做校验）。

因此本仓库默认把 `CONFIG_LOCALVERSION` 设为 **`-perf`**，内核自报 `4.14.180-perf`，
但这只是“名字”，真正保证兼容的是上面四个开关和 CRC。

---

## 2. 构建内容

| 项目 | 选择 | 说明 |
| --- | --- | --- |
| 内核源码 | [`PerezChilli/android_kernel_xiaomi_nabu`](https://github.com/PerezChilli/android_kernel_xiaomi_nabu) 分支 `nabu-w-oss-bks` | 专门为 HyperOS 3 / Android 16 适配的 4.14.180 树，含 Android 16 eBPF 回移、KGSL/DSI/电量计修复 |
| root | **BakaSU + SUSFS**（该分支已集成、上游维护者测过） | BakaSU 是 `tiann/KernelSU` 的下游分支，保留非 GKI 支持；官方 KernelSU 管理器可直接接管（`CONFIG_KSU_MULTI_MANAGER_SUPPORT=y`） |
| 编译器 | LLVM/Clang + LLD **20.1.8**（官方 release） | 与该 ROM 内核所用 clang 20 同代，源码树自带的 `build-recovery.sh` 会校验版本 |
| 打包 | AnyKernel3 | 只替换 boot 分区里的 kernel，保留原厂 ramdisk / 头 / vendor_boot dtb |

> 关于 KSU 版本：官方 KernelSU **1.0 起已放弃非 GKI**（最后支持非 GKI 的是 v0.9.5）。
> 4.14 内核要“最新一代 KSU 能力”，正确做法就是用 BakaSU / SukiSU 这类仍在维护非 GKI 的下游分支。
> 本流水线用的是源码树里已经集成、已配置好的 BakaSU，避免自己打 hook 补丁带来的不确定性。

### 性能 overlay（`configs/perf.fragment`，纯配置，不改源码）

| 选项 | 作用 |
| --- | --- |
| `CONFIG_TCP_CONG_BBR` + `CONFIG_DEFAULT_TCP_CONG="bbr"` + `CONFIG_NET_SCH_FQ` | 拥塞控制换 BBR、fq 排队，弱网/上传场景吞吐与延迟更好 |
| `CONFIG_NET_SCH_FQ_CODEL` / `CONFIG_NET_SCH_PIE` | 提供 AQM 备选（不改变默认） |
| `CONFIG_ZRAM_LZ4_COMPRESS` / `CONFIG_CRYPTO_LZ4HC` | zram 用 lz4 系列，6/8 GB 机器换页更快 |
| `CONFIG_IOSCHED_BFQ` | 让 BFQ 可用（默认仍是 CFQ，不改变行为） |
| `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y`，并显式关掉 `CC_OPTIMIZE_FOR_SIZE`、`DEBUG_INFO`、`SLUB_DEBUG`、`SCHED_DEBUG`、`FUNCTION_TRACER`、`KPROBES` | 与上游树保持一致的 -O2 + 无调试开销 |

设计原则是**只做“加开关”级别的改动**：不动调度器、不动 GPU/热、不打上游补丁，
这样 vendor 模块、SELinux、指纹/触控笔/键盘这些依赖内核 ABI 的东西不会被牵连。

---

## 3. 怎么跑

### 3.1 推到 GitHub

```bash
# 先在网页上建一个空仓库（不要勾选 README / .gitignore），例如 nabu-kernel
cd nabu-kernel-ci
git remote add origin https://github.com/<你的用户名>/nabu-kernel.git
git push -u origin main
```

### 3.2 触发构建

- 打开仓库 **Actions → nabu-kernel → Run workflow**；
- 参数：
  - `source_branch`：`nabu-w-oss-bks`（KSU+SUSFS，推荐）/ `nabu-w-oss-bk`（仅 KSU）/ `nabu-w-oss`（无 root）
  - `localversion`：默认 `-perf`
  - `perf_overlay`：默认开
- 一次构建约 **25–45 分钟**（1.9 GB 的 LLVM 下载 + 全量编译）。

### 3.3 产物

`Actions → 该次运行 → Artifacts`，包含：

```
nabu-<branch>-<run>.zip     # AnyKernel3 刷机包
Image                       # 原始 arm64 内核（未压缩，可自行重打包 boot.img）
SHA256SUMS
reference-config.diff       # olddefconfig 后的配置漂移，正常应接近空
```

日志里会打印 `Linux version ...`、`CONFIG_SMP/PREEMPT/MODVERSIONS` 与 `CONFIG_KSU*`，
用于确认“能给 vendor 模块加载”的四件套没被动过。

---

## 4. 刷入

> 前提：bootloader 已解锁，并且**先备份当前 boot 分区**（见第 5 节）。

**方式 A：KernelFlasher / 内核管理器 App（推荐）**
把 `nabu-kernel-*.zip` 拷进平板，用 KernelFlasher 直接选 zip 刷入（AnyKernel3 会自动处理 A/B 槽位）。

**方式 B：TWRP**
`adb push nabu-kernel-*.zip /sdcard/` → TWRP → Install → 选 zip → 刷完重启。

**方式 C：fastboot（需要自己出 boot.img）**
本仓库只产出 `Image`，因为 nabu 的 boot.img 里带着 ~96 MB 的 ramdisk，
必须用**本 ROM 原版 boot.img** 作底包重打包：

```bash
# 取出 ROM 里的 boot.img（7z 解压 images/boot.img），替换内核后重打包
# 需要 mkbootimg（Android 11+ header v3）：--header_version 3 --page_size 4096
fastboot flash boot boot-new.img
```

---

## 5. 回滚 / 备份

刷之前先备份（有 root 时）：

```bash
adb shell su -c "dd if=/dev/block/by-name/boot of=/sdcard/boot-stock.img"
adb pull /sdcard/boot-stock.img
```

出问题就 `fastboot flash boot boot-stock.img`；或者直接用 ROM 压缩包里的
`images/boot.img`（本仓库分析过的那份，内核为 4.14.180-moon-os3）。

---

## 6. 刷完后的验证清单

```bash
adb shell uname -a
# 期望：Linux localhost 4.14.180-perf ... aarch64

adb shell su -c id            # 期望 uid=0（KSU 管理器里授权后）
adb shell dmesg | grep -i -E 'ksu|susfs'
adb shell lsmod               # 期望 adsp/wcd/audio/cs35l41 等 dlkm 正常加载
```

功能面逐项过一遍：**wifi / 蓝牙 / 外放与耳机 / 麦克风 / 前后摄 / 触控与手写笔 / 键盘 /
自动亮度 / 充电与电量 / 指纹（无）/ 休眠唤醒**。任一模块加载失败，`dmesg` 里会有
`disagrees about version of symbol` 或 `version magic ... should be ...`，把日志发我即可定位。

---

## 7. 已知风险（请务必先看）

1. **未在真机验证**：本仓库是在你给的 ROM 包上做静态分析后搭的流水线，编译能过 ≠ 能开机。
   第一次刷请务必备份 boot，并准备好 ROM 原包救砖。
2. **CRC 假设**：vendor 模块能否加载取决于 `genksyms` 算出的符号 CRC 与 ROM 里模块一致。
   源码树是同一 4.14.180 基线，理论上一致；若不一致，日志会明确报 `disagrees about version of symbol`。
3. **root 检测**：BakaSU + SUSFS 已针对隐藏做配置，但银行/游戏类 App 的检测强度随时会变。
4. **SUSFS 许可证**：上游 SUSFS 标注 GPL-3.0，而内核树是 GPL-2.0-only，自行分发前请自行评估。

---

## 8. 目录

```
.github/workflows/build.yml   # CI 主流程
configs/perf.fragment         # 性能 overlay（追加到 profile-reference.config）
scripts/pack-anykernel.sh     # AnyKernel3 打包
```
