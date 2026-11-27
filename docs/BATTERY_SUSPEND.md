# 电池容量 / 熄屏休眠：证据、改动与排查

## 1. 电池容量：DT 是好的，内核也不是元凶

对 ROM 包里的 `dtbo.img` 做了解析（`nabu/parse_dtbo.py`，DTBO v1，1 个 entry，1462 个节点），
电池相关节点全部齐全且数值正确：

```
/fragment@99/__overlay__/qcom,battery-data/qcom,5119583_xiaomi_k82_p86120aa1_8720mah_averaged_masterslave_apr8th2021
    qcom,battery-type                  = 'K82_sunwoda_8720mah'
    qcom,nom-batt-capacity-mah         = 8720
    qcom,max-voltage-uv                = 4480000
    qcom,batt-id-kohm                  = 10
    qcom,profile-revision              = 24
    qcom,fg-profile-data               = 416 bytes
/fragment@20/__overlay__/qcom,pm8150b@2/qpnp,fg        -> qcom,battery-data = <&...>
/fragment@20/__overlay__/qcom,pm8150b@2/qcom,qpnp-smb5 -> qcom,battery-data = <&...>
```

也就是说：**8720 mAh、松下达电芯（K82_sunwoda）、4.48 V 满充** 这些关键参数在板级 DT 里是对的，
phandle 也正确挂到了 `qpnp,fg` 与 `qpnp-smb5` 上。

内核侧同样对得上：

| 项 | ROM 自带 moon 内核（从 boot.img 的 IKCONFIG 提取） | 本项目内核 |
| --- | --- | --- |
| `CONFIG_QPNP_FG_GEN4_NABU` | y | y |
| `CONFIG_QPNP_SMB5_NABU` | y | y |
| `CONFIG_QPNP_QNOVO5` | y | y |
| `CONFIG_POWER_SUPPLY` | y | y |
| `CONFIG_PM_AUTOSLEEP` | **未设置** | **y（本次新增）** |

`_NABU` 不是阉割版：Makefile 里 `CONFIG_QPNP_FG_GEN4_NABU += qpnp-fg-gen4-nabu.o`
（209 KB，比通用版 187 KB 更大），`QPNP_SMB5_NABU += smb5-lib-nabu.o`（290 KB）——
就是小米给 nabu 定制的那两份驱动，和原厂一致。

**结论**：容量异常不是 DT 配错、也不是驱动没编进去。剩下的可能按“先易后难”排序：

1. **framework 的 `power_profile.xml`**（来自移植源机型）里的 `battery.capacity`，
   Settings 里显示的“设计容量/电池容量”就是读它 → 只影响显示，与内核无关；
2. **vendor 的 health HAL / `vendor.battery.*` 属性**（移植包常见），表现为百分比不动、100% 卡死；
3. FG 的 **capacity-learning** 没触发（`/sys/class/power_supply/battery/charge_full`、
   `cycle_count` 不更新），这是 FG 算法层现象，需要日志才能定性；
4. 上一次刷的第三方内核把 FG 的 nvmem/profile 写坏（少见，可用 `qpnp-fg-gen4` 的
   `profile-load` 诊断节点确认）。

在设备上跑一条命令就能把 1–4 区分开：

```bash
adb shell su -c sh /data/local/tmp/battery-diag.sh
```

脚本内容见 `scripts/ondevice-diag.sh`（会 dump 所有 power_supply 节点的 uevent、FG 的 dmesg、
wakelock 列表、`/sys/power/*` 状态），把输出给我就能定位到具体层。

> 说明：内核能直接修的只有第 3、4 类。1、2 类必须改 ROM（framework-res / vendor），
> 不是换内核能解决的——所以本次没有为了“看起来改了”而往驱动里塞投机补丁。

## 2. 熄屏休眠：autosleep + 屏幕状态门控

原厂配置 `# CONFIG_PM_AUTOSLEEP is not set`，内核只提供 `/sys/power/state` +
`/sys/power/wakeup_count` 这条需要 userspace 配合的路径。移植 ROM 的 SystemSuspend 一旦不工作，
屏幕关了也进不了 suspend（iodé 社区在 nabu 上测到过 **>15%/小时** 的待机耗电，PixelOS/EvolutionX
的 nabu 更新日志里也专门写了 "deep sleep issue fixed"）。

本次在 `configs/suspend.fragment` 增加：

```
CONFIG_PM_AUTOSLEEP=y
```

并应用两个源码补丁（只在 `autosleep_default=true` 时应用）：

1. `patches/0001-autosleep-default-mem.patch`：把 `autosleep_state` 的初值改成 `PM_SUSPEND_MEM`。
   注意：这只改变量，**不会排队挂起工作**，单独用会"报告 mem 但永不入睡"。
2. `patches/0002-autosleep-screen-gate.patch`：新增 `kernel/power/nabu_autosleep_gate.c`。
   autosleep 的语义是"没有 wakelock 就挂起"，而移植 ROM 亮屏时不持 wakelock，无条件 arm 会变成
   使用中反复 suspend/resume（闪黑）。门控用树里已有的 `drm_notifier`
   （`drivers/gpu/drm/msm/dsi-staging/dsi_drm.c`）：
   - `DRM_EVENT_BLANK` + `DRM_BLANK_POWERDOWN`（面板已断电）→ `pm_autosleep_set_state(PM_SUSPEND_MEM)`
   - `DRM_EARLY_EVENT_BLANK` + `DRM_BLANK_UNBLANK`（点亮前）→ `pm_autosleep_set_state(PM_SUSPEND_ON)`
   - `late_initcall` 先置 `PM_SUSPEND_ON`，开机不 arm。

   `build.yml` 用 `git apply` 添加新文件，再用 `printf` 往 `kernel/power/Makefile` 追加
   `obj-$(CONFIG_PM_AUTOSLEEP) += nabu_autosleep_gate.o`，这样不依赖 Makefile 行的上下文，
   内核树改格式也不会把构建弄挂。

开机后 `/sys/power/autosleep` 是 `off`，熄屏才会变 `mem`。回退方案（`autosleep_default=false`
或不带门控的内核）等价手动操作：

```bash
adb shell su -c 'echo mem > /sys/power/autosleep'   # 熄屏
adb shell su -c 'echo off > /sys/power/autosleep'   # 亮屏
```

验证是否真的睡了：

```bash
adb shell su -c 'cat /sys/power/suspend_stats/success'   # 数字应持续增长
dmesg | grep -i -E 'nabu-autosleep|PM: suspend|Suspended for'
```

如果 `suspend_stats/fail` 在涨，`dmesg` 里会给出失败原因（常见是某个驱动 `-EBUSY`），
把那段贴出来就能定位到具体 wakelock/driver。

> 插着 USB 调试时 autosleep 的 work 会阻塞在 `pm_get_wakeup_count(block=true)`：
> USB 持续产生未消费的 wakeup event，内核根本不会尝试挂起（`suspend_stats` 不动）。
> 这是内核正常行为，所以**验证入睡必须拔掉数据线**。

### 设备验证状态（2026-11-27，build #35）

- ✅ 开机不 arm（`autosleep=off`），首个 `UNBLANK` 打印 `display on, disarming autosleep`
- ✅ 亮屏静置 3 分 20 秒：`success=0 fail=0`，无 `PM: suspend` 记录
- ✅ 熄屏打印 `display off, arming autosleep`，`autosleep=mem`；点亮后恢复 `off`
- ⏳ **拔线熄屏后 `success` 增长尚未实测**：本会话无法物理拔线，且测试机同时被另一会话占用
  （中途被卸载管理器、被重启过），这一步需要人工按第 4 条清单确认。

## 3. 本次内核相对原厂配置的全部差异

配置项差异除 KSU/SUSFS 外只有 `CONFIG_PM_AUTOSLEEP=y`（`perf` 档位另有下表调优项）。

| 选项 | 原厂 | 现在 | 目的 |
| --- | --- | --- | --- |
| `CONFIG_PM_AUTOSLEEP` | n | **y** | 熄屏自动 suspend |
| `CONFIG_TCP_CONG_ADVANCED` / `BBR` / `DEFAULT_BBR` | n | **y** | 网络吞吐/延迟 |
| `CONFIG_NET_SCH_FQ` / `FQ_CODEL` / `PIE` | n | **y** | 队列调度 |
| `CONFIG_IOSCHED_BFQ` | n | **y** | 可选 IO 调度器（默认仍 CFQ） |
| `CONFIG_SCHED_DEBUG` | y | **n** | 去掉调度器调试开销 |
| `CONFIG_CRYPTO_LZ4HC` | n | **y** | zram 可选 lz4hc |
