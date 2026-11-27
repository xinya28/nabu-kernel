[![](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)

# nabu kernel builds

面向 **小米平板 5（nabu / SM8150-AC / Snapdragon 860）** 的 4.14.180 内核构建流水线。
源码基线是 [PerezChilli/android_kernel_xiaomi_nabu](https://github.com/PerezChilli/android_kernel_xiaomi_nabu)，
目标 ROM 是移植版 HyperOS 3 / Android 16（`OS3.0.304.0.WNSCNXM`）。

本仓库不存内核源码，只放 **CI 配方 + 配置片段 + 补丁**，构建产物（`Image` / AnyKernel3 zip）由 GitHub Actions 产出。

## 两种构建档位

| 档位 | 用途 | workflow_dispatch 输入 |
|---|---|---|
| ROM 原样 + 休眠 | 只在内核里加熄屏挂起，其余与 ROM 自带内核一致 | `source_branch=nabu-w-oss-bks`、`perf_overlay=false`、`autosleep_default=true`、`ksu_source=tree` |
| 性能 + KSU | 额外加 BBR / fq_codel / BFQ 等调优 | `perf_overlay=true`，其余同上 |

`perf.fragment` 里的每一项都是上游 4.14 已有选项，不改源码，所以厂商模块的 `vermagic` 仍然对得上；
实际落地的选项可以看构建产物里的 `reference-config.diff`。

## 两个必须知道的结论

### 1. KSU 管理器只能用同一家

树内自带的 KernelSU 是 **ReSukiSU / BakaSU 系**，不是官方实现。匹配的管理器是
[`BakaSU v4.2.0-rc3 (35286)`](https://github.com/Baka-SU/BakaSU)（包名 `com.resukisu.resukisu`）。

换成官方 KernelSU v0.9.5 或 KernelSU-Next 都会失败：

- 官方 v0.9.5 → 非 GKI 场景下 `su` 不会出现
- KernelSU-Next `v1.0.3-10-legacy` → 管理器首页直接报「不支持 — KernelSU 现在只支持 GKI 内核」

驱动版本比管理器新时会提示「需要更新管理器」，用 35286 这一版即可对齐。

**SUSFS 与 SU 授权无关**：它只负责隐藏/伪装（`su` 路径、mount、uname 等），
内核不带 SUSFS 时管理器只是把那一栏显示为不可用，模块管理和授权照常工作。

### 2. autosleep 必须按屏幕状态门控

4.14 默认没有 autosleep。加上 `CONFIG_PM_AUTOSLEEP=y` 只是让 `/sys/power/autosleep` 出现；
仅把源码里的 `autosleep_state` 赋值为 `PM_SUSPEND_MEM` **不会排队挂起工作**，
内核会"报告 mem 但永不入睡"，`/sys/power/suspend_stats` 始终 0/0。

要真正挂起必须走 `pm_autosleep_set_state()`，但**不能开机就无条件 arm**：
autosleep 的语义是"没有 wakelock 就立刻挂起"，而该移植 ROM 在亮屏时并不持有 wakelock，
无条件 arm 会让设备在使用中反复 suspend/resume，表现为屏幕固定频率闪黑。

所以本仓库加了 `kernel/power/nabu_autosleep_gate.c`
（`patches/0002-autosleep-screen-gate.patch`，构建时由 `build.yml` 应用并把目标文件追加进
`kernel/power/Makefile`）：

- `late_initcall` 先 `pm_autosleep_set_state(PM_SUSPEND_ON)`——开机不 arm，等屏幕状态明确；
- 注册树里已有的 `drm_notifier`（实现见 `drivers/gpu/drm/msm/dsi-staging/dsi_drm.c`，
  `EXPORT_SYMBOL`；NVT 触控与 xiaomi-keyboard 也在用）：
  - 面板**真正断电后**（`DRM_EVENT_BLANK` + `DRM_BLANK_POWERDOWN`）→ `PM_SUSPEND_MEM`；
  - **点亮前**（`DRM_EARLY_EVENT_BLANK` + `DRM_BLANK_UNBLANK`）→ `PM_SUSPEND_ON`。

`autosleep_default=false` 时既不应用补丁也不加配置，可退回纯用户态方案
（熄屏 `echo mem > /sys/power/autosleep`，亮屏 `echo off`）。

#### 设备验证记录（2026-11-27，build #35，`fastboot boot` 临时启动）

已验证：

- 开机 1.5 s 注册门控，`/sys/power/autosleep` 为 `off`；13.9 s 首个 `UNBLANK` 打印
  `display on, disarming autosleep`；
- 亮屏静置 **3 分 20 秒**（17:33:50–17:37:10）：`success=0 fail=0`，`/sys/power/autosleep=off`，
  dmesg 无任何 `PM: suspend` 记录——亮屏不再有挂起尝试；
- 按电源键熄屏：打印 `display off, arming autosleep`，`/sys/power/autosleep=mem`；
  再点亮：`display on, disarming autosleep`，回到 `off`；
- **熄屏后确实进入 deep suspend**：17:53–17:54 熄屏期间 `success=14`、`fail=1`
  （`last_failed_dev=alarmtimer`、`-EBUSY`，属良性否决），dmesg 有 15 条
  `PM: suspend entry (deep)` / `suspend exit` 记录；点亮后 `display on, disarming autosleep`，
  autosleep 立刻回到 `off`；
- `su -c id` 正常（`context=u:r:ksu:s0`），KSU 模块与内核版本未受影响。

**尚未验证 / 注意（如实记录）**：

- **纯拔线连续睡眠时长**：本会话无法物理拔掉数据线。上面的 14 次挂起是在**插着 USB** 时
  测到的：USB 事件会不断把设备唤醒，于是形成"熄屏 → 入睡 → 被 USB 唤醒 → 再入睡"的循环
  （屏幕本来就是灭的，不会闪屏）。**"拔线后连续睡 2 分钟以上"的时长仍需人工确认**，
  预期会明显优于插线场景。
- **管理器首页「工作中 Built-in」**：测试期间另一个会话把 `com.resukisu.resukisu`
  从设备上卸载了（本仓库同时被另一会话推送构建），所以这一项本次没有重新截图确认；
  `su` 与模块挂载正常。

## 怎么读 suspend_stats

```
success=11  fail=50  last_failed_dev=alarmtimer  last_failed_errno=-16
```

`fail` 不是故障，而是**挂起被否决**的次数，`-16` 即 `-EBUSY`（"现在别睡，有东西要跑"）。
最常见的良性否决是 `alarmtimer`：有即将到期的唤醒定时器时它的 `suspend` 回调就返回 `-EBUSY`。
插着充电线时 `typec-cc-state-change` / `usbin-uv` / `ssusb` 等事件会**把设备反复唤醒**，
表现是熄屏期间 `success` 快速增长、入睡时长很短（屏幕灭着，用户看不到）；
所以测"能连续睡多久"一定要**拔掉数据线**。

## 验证清单

1. `su -c id` 返回 `uid=0(root) ... context=u:r:ksu:s0` — ✅ 2026-11-27 已验证
2. 管理器首页显示「工作中 Built-in」，模块数量与 `/data/adb/modules` 一致 — ⚠️ 本次被另一会话卸载了管理器，未复测
3. 亮屏放置数分钟：屏幕不闪黑、`suspend_stats` 不增长 — ✅ 3 分 20 秒 0/0
4. 拔线熄屏数分钟：`success` 增长，`/sys/power/autosleep` 为 `mem` — ✅ `success` 增长已验证
   （插 USB 时 14 次 deep suspend）；⏳ 纯拔线连续睡眠时长待人工确认

验证一律先 `fastboot boot` 临时启动，确认无误再刷写。

## 产物与刷写

| 文件 | 用途 |
|---|---|
| `boot-nabu-rom-suspend.img` | 直接 `fastboot boot` / `fastboot flash boot` |
| `nabu-kernel-suspend-anykernel3.zip` | Recovery 或 KSU 管理器内刷入，自动写 `boot` 分区 |
| `Image` | 裸内核，`.img` 里被替换的那一段 |

`boot.img` 是 header v3、ramdisk 保持原样，只替换内核；`tools/repack_boot.js` 做过往返校验（改完再还原与原文件字节一致）。

## 许可

本仓库的 CI 脚本、配置片段与补丁以 **GPL-2.0-only** 发布，与 Linux 内核保持一致（见 `LICENSE`）。
内核源码版权归各自作者所有；构建产物受上游内核的 GPL-2.0 约束。

## 致谢

- [PerezChilli/android_kernel_xiaomi_nabu](https://github.com/PerezChilli/android_kernel_xiaomi_nabu) — 内核源码树
- [Baka-SU/BakaSU](https://github.com/Baka-SU/BakaSU) — 树内使用的 KernelSU 下游实现与管理器
- [tiann/KernelSU](https://github.com/tiann/KernelSU) — KernelSU 上游
