<div align="center">

# nabu-HyperOS3-A16 · kernel

### 小米平板 5（nabu）HyperOS 3 / Android 16 的内核构建配方

![powered by dsh](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)
![device](https://img.shields.io/badge/device-nabu_%2F_Xiaomi_Pad_5-orange?style=flat-square)
![source](https://img.shields.io/badge/source-HyperOS_3_%2F_Android_16-blue?style=flat-square)
![kernel](https://img.shields.io/badge/kernel-4.14.180_%2B_nabu_drivers-blue?style=flat-square)
![CI](https://img.shields.io/badge/CI-GitHub_Actions-green?style=flat-square)
![license](https://img.shields.io/badge/license-GPL--2.0--only-orange?style=flat-square)

</div>

本分支是 `nabu-HyperOS3-A16` 的**内核分支**，存放内核构建的全部内容。项目总览、产物下载与刷写回滚说明见
`main` 分支，管理器的改包/去特征流水线见 `su-manager` 分支。

面向 **小米平板 5（nabu / SM8150-AC / 骁龙 860）** 的 Linux 4.14.180 内核构建配方。

- **目标设备**：小米平板 5（nabu），A/B 分区，bootloader 已解锁
- **目标 ROM**：移植版 HyperOS 3 / Android 16（`OS3.0.304.0.WNSCNXM`）
- **源码基线**：[PerezChilli/android_kernel_xiaomi_nabu](https://github.com/PerezChilli/android_kernel_xiaomi_nabu) 分支 `nabu-w-oss-bks`
- **性质**：本仓库**不存放内核源码**，只包含 CI 流程、配置片段、补丁与打包工具；构建产物由 GitHub Actions 产出

## 功能特性

| 类别 | 内容 |
|---|---|
| 熄屏休眠 | `CONFIG_PM_AUTOSLEEP=y` + 屏幕状态门控（`msm_drm_notifier`）：熄屏才允许挂起，亮屏立即禁止，避免使用中闪黑 |
| 网络 | BBR 拥塞控制（`DEFAULT_TCP_CONG=bbr`）、`fq` / `fq_codel` / `pie` 队列调度 |
| I/O | BFQ 可用（默认仍为 CFQ，由 ROM 决定是否切换） |
| 编译 | `CC_OPTIMIZE_FOR_PERFORMANCE`，关闭 `DEBUG_INFO` / `SLUB_DEBUG` / `SCHED_DEBUG` / `FUNCTION_TRACER` |
| 安全 | `/proc/kallsyms` 权限由 `0444` 收紧为 `0400`，非 root 进程无法读取内核符号 |
| 兼容性 | 保留 `CONFIG_KPROBES`（KernelSU 依赖）与厂商模块所需的 `vermagic` 配置项 |

所有改动均通过配置文件或 `patches/` 中的补丁实现，不修改上游源码逻辑，厂商内核模块可继续加载。
实际生效的选项请查阅构建产物中的 `reference-config.diff`。

## 两种构建档位

| 档位 | 说明 | `workflow_dispatch` 输入 |
|---|---|---|
| **ROM 原样 + 休眠** | 仅增加熄屏休眠，其余与 ROM 自带内核一致 | `source_branch=nabu-w-oss-bks`、`perf_overlay=false`、`autosleep_default=true`、`ksu_source=tree` |
| **性能档** | 额外启用的网络 / I/O / 编译优化 | `perf_overlay=true`，其余同上 |

单次构建约 18 分钟。

## 已知结论

以下结论均来自真机验证，可避免重复排查：

1. **KernelSU 必须使用同系管理器。** 内核内置的是 ReSukiSU / BakaSU 系实现（UAPI `35286/6`）。
   官方 KernelSU v0.9.5 在非 GKI 下不会提供 `su`；KernelSU-Next 会提示"只支持 GKI 内核"。
2. **仅设置 `autosleep` 变量不会触发挂起**，必须经 `pm_autosleep_set_state()`。
   且不可无条件启用：该 ROM 亮屏时不持有 wakelock，无条件 `autosleep = mem` 会导致使用中周期性熄屏。
3. **`/proc/kallsyms` 默认为全局可读**，是 KSU 被原生检测识别的主要指纹，已在构建中收紧为 `0400`。
4. **`suspend_stats` 中的 `fail` 与 `last_failed_dev=alarmtimer`（`-EBUSY`）属正常否决**，不是故障。
   调试休眠时请拔掉数据线——USB 会持续持有唤醒源。

## 刷写

```bash
# 临时启动验证（不写入分区，重启即恢复）
fastboot boot boot-nabu-perf-suspend.img

# 确认无误后刷入当前槽（本机为 _a）
fastboot flash boot_a boot-nabu-perf-suspend.img

# 回滚到 ROM 原厂内核
fastboot flash boot_a <ROM 包内的 boot.img>
```

也可在 Recovery 或 KSU 管理器内刷入 `nabu-kernel-perf-suspend-anykernel3.zip`。

`boot.img` 为 header v3 格式，仅替换内核，ramdisk 保持原样；`tools/repack_boot.js` 已做过去回字节校验。

## 实测数据

| 项目 | 结果 |
|---|---|
| 权限 | `su -c id -u` → `0` |
| 内核符号 | `ls -l /proc/kallsyms` → `-r--------` |
| 拥塞控制 | `tcp_congestion_control` → `bbr` |
| 熄屏门控 | `mWakefulness=Asleep` → `autosleep=mem`；`Awake` → `off` |
| 待机电流 | 约 **18.6 mA**（拔线熄屏实测，约 5% / 天） |
| 深度休眠 | `PM: suspend entry (deep)`，单次实测最长 2 分 31 秒 |

## 目录结构

```
.github/workflows/build.yml            内核构建
configs/perf.fragment                  性能相关配置项
configs/suspend.fragment               熄屏休眠配置项
patches/0001-autosleep-default-mem.patch
patches/nabu_autosleep_gate.c          屏幕状态门控实现
tools/repack_boot.js                   替换 boot.img 中的内核
scripts/                               AnyKernel3 打包与真机诊断脚本
docs/                                  设计与排查记录
battery-overlay/                       电池容量 RRO（已拆分到独立仓库 nabu-battery-fix，此处为原副本）
```

> 本分支保留了拆分前的完整快照（含 `build-manager.yml` 与 `manager-repack/`、`battery-overlay/` 的原副本）。
> 管理器流水线以 `su-manager` 分支为准，电池容量修正以独立仓库
> [nabu-battery-fix](https://github.com/xinya28/nabu-battery-fix) 为准。

## 配套管理器

内核侧 KernelSU 必须搭配同系管理器使用，详见 [发布页](https://github.com/xinya28/nabu-HyperOS3-A16/releases) 中的两个变体说明；
管理器改包/去特征流水线在 `su-manager` 分支。
改包名版本会移除若干可被检测的特征（原生库名、Application 类、zygote preload、启动类名、应用标签），
代价是 LKM 模式（magica / late load）不可用；内置内核模式不受影响。

## 许可

本项目以 **GPL-2.0-only** 发布，全文见 [LICENSE](LICENSE)。
第三方组件及其许可条款见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 致谢

- [PerezChilli/android_kernel_xiaomi_nabu](https://github.com/PerezChilli/android_kernel_xiaomi_nabu) —— nabu 内核源码树，本项目全部构建的基础
- [Baka-SU/BakaSU](https://github.com/Baka-SU/BakaSU) —— 内核内置的 KernelSU 下游实现及配套管理器
- [tiann/KernelSU](https://github.com/tiann/KernelSU) —— KernelSU 上游项目
- [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) —— AnyKernel3 刷写模板
- [iBotPeaches/Apktool](https://github.com/iBotPeaches/Apktool) —— 资源解码与重打包
- 以及 xda-developers、酷安等社区中公开 nabu 内核与 HyperOS 移植资料的同好

## 免责声明

修改内核与刷写分区存在风险，可能导致设备无法启动或数据丢失。本项目仅供个人研究与自用，
使用前请自行备份数据，并确保已掌握回滚方法。本项目与小米、Google 及上述上游项目维护者均无隶属关系。
