[![](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)

# nabu-kernel — 小米平板 5（nabu）4.14.180 内核构建流水线

用 GitHub Actions 给 **小米平板 5 / nabu（SM8150-AC，骁龙 860）** 编译 4.14.180 内核，
适配 HyperOS 3 移植包 `OS3.0.304.0.WNSCNXM_16.0`。

---

## 为什么是 4.14.180 而不是 4.19

对 ROM 包做了字节级分析：

| 检查项 | 实测结果 |
| --- | --- |
| `boot.img` | header v3，内核是**未压缩 arm64 `Image`**（`ARMd` @0x38） |
| 内核版本串 | `Linux version 4.14.180-moon-os3-ga5805c039` |
| `super.img` 里 vendor 模块 | `vermagic=4.14.180-perf-gde52a0344e18 SMP preempt mod_unload modversions aarch64` |
| 是否存在 4.19 模块 | 否，全盘只有 4.14.180 一种 |

`kernel/module.c` 的 `same_magic()` 在 `CONFIG_MODVERSIONS=y` 时**跳过 vermagic 的版本号段**，
只比对 `SMP preempt mod_unload modversions aarch64` 与符号 CRC。所以内核 release 串可以是
`4.14.180-perf`，vendor 的 `adsp_dlkm` / `wcd_dlkm` / `audio_dlkm` / `machine_dlkm` 等模块照常加载。
这也是本项目能保障「系统功能正常」的前提。

## 内置修复与优化

| 项目 | 内容 | 状态 |
| --- | --- | --- |
| 熄屏休眠 | `CONFIG_PM_AUTOSLEEP=y` + `patches/0001-autosleep-default-mem.patch`（`autosleep_state = PM_SUSPEND_MEM`） | ✅ 实测 `suspend_stats/success=13`，`dmesg` 成对 `PM: suspend entry (deep)` |
| 网络 | BBR + `fq`/`fq_codel`/`pie` | ✅ |
| IO / 内存 | `IOSCHED_BFQ` 可选、zram `lz4hc` | ✅ |
| 调试开销 | `SCHED_DEBUG`、`FUNCTION_TRACER`、`KPROBES`、`DEBUG_INFO` 关闭 | ✅ |
| root | 可在 BakaSU 与 **官方 KernelSU v0.9.5** 之间切换（`ksu_source` 输入） | 🔧 |
| 电池容量显示 | framework `power_profile.xml` 写死 `battery.capacity=1000` | ❌ 内核侧无解（见下） |
| 写字时蓝牙/音频断流 | —— | ❌ 内核侧已排除（见下） |

## 已知问题（诚实记录）

**电池容量显示 1000 mAh**：`framework-res.apk` 的 `res/xml/power_profile.xml` 里
`battery.capacity` 是移植时留下的占位值。内核上报是对的（`charge_full=8688 mAh`、
`charge_full_design=8720 mAh`、`health=Good`）。替换 `framework-res.apk` 已在真机验证
会导致 system_server 起不来（`battery` 服务注册失败、zygote 反复重启），因此不做。

**笔一动就断流**：已排除触控中断抢占（音频线程本就在大核）、笔的 BLE 共存、A2DP offload、
SELinux 拒绝、动态刷新率、高码率编解码器六种假设。旧 ROM 60Hz 不断、新 ROM 60/120Hz 都断，
指向移植包系统层的带宽/调度基线，属内核之外。

## 构建

```
Actions → nabu-kernel → Run workflow
  source_branch      nabu-w-oss-bks / nabu-w-oss-bk / nabu-w-oss
  localversion       -perf
  perf_overlay       true
  autosleep_default  true
  ksu_source         tree（BakaSU）/ official-v0.9.5
  ksu_version        可选，钉住 KSU_VERSION（用于匹配管理器版本号）
```

工具链 LLVM/Clang + LLD **20.1.8**，产物：

```
nabu-kernel-<branch>-<sha>.zip   AnyKernel3 刷机包
Image                            未压缩 arm64 Image
SHA256SUMS / reference-config.diff
```

## 本地工具

- `tools/repack_boot.js` — 用 ROM 原版 `boot.img` 替换内核重打包（header v3）。
  已用本项目 ROM 的 boot.img 做过**往返验证：重打包结果与原文件 0 字节差异**。

```bash
node tools/repack_boot.js boot.img Image boot-new.img
fastboot flash boot boot-new.img
```

- `scripts/ondevice-diag.sh` — 电池/休眠/中断现场取证（需 root）
- `scripts/ondevice-stylus-diag.sh` — 笔与蓝牙音频断流取证（A/B 两段对比）

## 目录

```
.github/workflows/build.yml   CI 主流程
configs/perf.fragment         性能 overlay
patches/                      内核补丁（autosleep 默认 mem）
scripts/                      打包与真机取证脚本
tools/repack_boot.js          boot.img 重打包
docs/                         分析与结论（电池/休眠、断流）
```

## 说明

内核源码来自 [`PerezChilli/android_kernel_xiaomi_nabu`](https://github.com/PerezChilli/android_kernel_xiaomi_nabu)
（HyperOS 3 / Android 16 适配的 4.14.180 树）。编译通过不代表能开机，
首次刷写请先备份 boot 分区。
