<div align="center">

# nabu-HyperOS3-A16

### 小米平板 5（nabu）HyperOS 3 / Android 16 的内核与 KSU 管理器构建仓库

![powered by dsh](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)
![device](https://img.shields.io/badge/device-nabu_%2F_Xiaomi_Pad_5-orange?style=flat-square)
![source](https://img.shields.io/badge/source-HyperOS_3_%2F_Android_16-blue?style=flat-square)
![kernel](https://img.shields.io/badge/kernel-4.14.180_%2B_nabu_drivers-blue?style=flat-square)
![CI](https://img.shields.io/badge/CI-GitHub_Actions-green?style=flat-square)
![license](https://img.shields.io/badge/license-GPL--2.0--only-orange?style=flat-square)

</div>

面向 **小米平板 5（nabu / SM8150-AC / 骁龙 860）** 移植版 HyperOS 3 / Android 16（`OS3.0.304.0.WNSCNXM`）
的内核构建配方与配套 KernelSU 管理器配方。本仓库**不存放内核源码**，只提供可复现的 CI 流程、
配置片段、补丁与打包脚本，产物由 GitHub Actions 构建。

## 项目定位

| 项 | 取值 |
|---|---|
| 设备 | 小米平板 5（nabu），A/B 分区，bootloader 已解锁 |
| 系统 | 移植版 HyperOS 3 / Android 16（`OS3.0.304.0.WNSCNXM`） |
| 内核 | Linux **4.14.180**（必须 4.14：ROM 的 `/vendor/lib/modules` 只接受该 vermagic） |
| 源码基线 | [PerezChilli/android_kernel_xiaomi_nabu](https://github.com/PerezChilli/android_kernel_xiaomi_nabu) 分支 `nabu-w-oss-bks` |
| Root | BakaSU / ReSukiSU 系（KernelSU 下游，uapi 6，非 GKI）+ SUSFS |
| 许可 | GPL-2.0-only |

## 分支导航

本仓库按产物拆分为三条分支，`main` 只做文档索引，不含任何 workflow 代码：

| 分支 | 内容 |
|---|---|
| **`main`**（默认） | 本页：项目总览、分支导航、产物下载、刷写与回滚、已知结论、许可与致谢 |
| **`kernel`** | 内核构建全部内容：`.github/workflows/build.yml`、`configs/`、`patches/`、`tools/`、`scripts/`、`docs/` |
| **`su-manager`** | 管理器构建：`.github/workflows/build-manager.yml`、`manager-repack/`（改包名 / 去特征 / 固定签名） |

历史遗留分支 `stylus-bt-audio`、`stylus-fix-old` 保留未删，仅作记录，不属于当前构建路径。

## 两套产物

### 1. 内核

由 `kernel` 分支的 `build.yml` 构建，产物发布在
**[Releases](https://github.com/xinya28/nabu-HyperOS3-A16/releases)**：

| 文件 | 用途 |
|---|---|
| `nabu-kernel-perf-suspend-anykernel3.zip` | AnyKernel3 刷写包，Recovery / KSU 管理器直接刷 |
| `boot-nabu-perf-suspend.img` | 完整 boot.img（header v3，仅替换内核），fastboot 刷入 |
| `Image` | 裸内核镜像 |
| `reference-config.diff` | 实际生效的配置项与基线差异 |
| `SHA256SUMS` | 上述文件校验和 |

两种构建档位（`workflow_dispatch` 输入）：

| 档位 | 输入 | 说明 |
|---|---|---|
| ROM 原样 + 休眠 | `source_branch=nabu-w-oss-bks`、`perf_overlay=false`、`autosleep_default=true`、`ksu_source=tree` | 只加熄屏休眠，其余与 ROM 自带内核一致 |
| 性能档 | `perf_overlay=true`，其余同上 | 额外启用网络 / I/O / 编译优化（BBR、BFQ、`CC_OPTIMIZE_FOR_PERFORMANCE` 等） |

单次构建约 18 分钟。`build.yml` 的 `concurrency` 为 `cancel-in-progress: true`，**有内核构建在跑时不要 push**。

### 2. 配套管理器（KSU Manager）

由 `su-manager` 分支的 `build-manager.yml` 构建，产物为 Actions artifact
（`ksu-manager_<package>_<versionCode>.apk`，保留 30 天）；已在 v1.0.0 Release 中附带一份：

- `manager-Baka-com.quietforest.systemservice-35286.apk`：改包名 / 去特征版本（推荐）
- `manager-BakaSU-35286-original.apk`：同版本上游原包，用于对照

内核内置的 KernelSU 必须搭配**同系管理器**：官方 KernelSU v0.9.5 在非 GKI 下不提供 `su`，
KernelSU-Next 会提示"只支持 GKI 内核"。改包名版本移除了若干可被原生检测抓取的特征
（native 库名、Application 类、zygote preload、启动类名、应用标签），代价是 LKM 模式
（magica / late load）不可用，内置内核模式不受影响。

首次使用改包管理器需授权一次（重启有效，证书不变则重建 APK 后无需重做）：

```sh
su -c '/data/adb/ksu/bin/ksud kernel dynamic-manager set-apk <apk 路径>'
su -c '/data/adb/ksu/bin/ksud kernel dynamic-manager get --internal true'
```

## 刷写与回滚

```bash
# 临时启动验证（不写入分区，重启即恢复）
fastboot boot boot-nabu-perf-suspend.img

# 确认无误后刷入当前槽（本机为 _a）
fastboot flash boot_a boot-nabu-perf-suspend.img

# 回滚到 ROM 原厂内核
fastboot flash boot_a <ROM 包内的 boot.img>
```

也可在 Recovery 或 KSU 管理器内刷入 `nabu-kernel-perf-suspend-anykernel3.zip`。
`boot.img` 为 header v3 格式，只替换内核，ramdisk 保持原样（`tools/repack_boot.js` 做过回字节校验）。

## 已知结论

以下结论均来自真机验证，可避免重复排查：

1. **KernelSU 必须使用同系管理器。** 内核内置 ReSukiSU / BakaSU 系实现（UAPI `35286/6`）；
   官方 KernelSU v0.9.5 在非 GKI 下不提供 `su`，KernelSU-Next 直接拒绝 GKI 以外的内核。
2. **仅设置 `autosleep` 变量不会触发挂起**，必须经 `pm_autosleep_set_state()`。
   且不可无条件启用：该 ROM 亮屏时不持有 wakelock，无条件 `autosleep = mem` 会导致使用中周期性熄屏，
   所以内核加了屏幕状态门控（`msm_drm_notifier`）：熄屏才允许挂起，亮屏立即禁止。
3. **`/proc/kallsyms` 默认为全局可读**，是 KSU 被原生检测识别的主要指纹，构建中已收紧为 `0400`
   （`ls -l /proc/kallsyms` → `-r--------`）。
4. **`suspend_stats` 里的 `fail` 与 `last_failed_dev=alarmtimer`（`-EBUSY`）属正常否决**，不是故障；
   调试休眠时请拔掉数据线——USB 会持续持有唤醒源。

## 实测数据

| 项目 | 结果 |
|---|---|
| 权限 | `su -c id -u` → `0` |
| 内核符号 | `ls -l /proc/kallsyms` → `-r--------` |
| 拥塞控制 | `tcp_congestion_control` → `bbr` |
| 熄屏门控 | `mWakefulness=Asleep` → `autosleep=mem`；`Awake` → `off` |
| 待机电流 | 约 **18.6 mA**（拔线熄屏实测，约 5% / 天） |
| 深度休眠 | `PM: suspend entry (deep)`，单次实测最长 2 分 31 秒 |

## 相关仓库

| 仓库 | 内容 |
|---|---|
| [nabu-battery-fix](https://github.com/xinya28/nabu-battery-fix) | 电池容量显示修正（静态 RRO 把 `battery.capacity` 1000 → 8720 mAh） |
| [nabu-adb-enable](https://github.com/xinya28/nabu-adb-enable) | ADB 常驻开启 KSU 模块（开机恢复 USB 调试授权） |

## 目录结构

本分支只有三个文件：

```
README.md                本页
LICENSE                  GPL-2.0 全文
THIRD_PARTY_NOTICES.md   第三方组件与许可声明
```

内核构建内容见 `kernel` 分支，管理器内容见 `su-manager` 分支。

## 许可与致谢

本项目以 **GPL-2.0-only** 发布，全文见 [LICENSE](LICENSE)；第三方组件及其条款见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

- [PerezChilli/android_kernel_xiaomi_nabu](https://github.com/PerezChilli/android_kernel_xiaomi_nabu) —— nabu 内核源码树
- [Baka-SU/BakaSU](https://github.com/Baka-SU/BakaSU) —— 内核内置的 KernelSU 下游实现及配套管理器
- [tiann/KernelSU](https://github.com/tiann/KernelSU) —— KernelSU 上游
- [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) —— AnyKernel3 刷写模板
- [iBotPeaches/Apktool](https://github.com/iBotPeaches/Apktool) —— 资源解码与重打包
- 以及 xda-developers、酷安等社区公开 nabu 内核与 HyperOS 移植资料的同好

## 免责声明

修改内核与刷写分区存在风险，可能导致设备无法启动或数据丢失。本项目仅供个人研究与自用，
使用前请自行备份数据并确认已掌握回滚方法。本项目与小米、Google 及上述上游项目维护者均无隶属关系。
