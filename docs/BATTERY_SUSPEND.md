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

## 2. 熄屏休眠：本次真的改了

原厂配置 `# CONFIG_PM_AUTOSLEEP is not set`，内核只提供 `/sys/power/state` +
`/sys/power/wakeup_count` 这条需要 userspace 配合的路径。移植 ROM 的 SystemSuspend 一旦不工作，
屏幕关了也进不了 suspend（iodé 社区在 nabu 上测到过 **>15%/小时** 的待机耗电，PixelOS/EvolutionX
的 nabu 更新日志里也专门写了 "deep sleep issue fixed"）。

本次在 `configs/perf.fragment` 增加：

```
CONFIG_PM_AUTOSLEEP=y
```

效果：出现 `/sys/power/autosleep`，写入 `mem` 后**内核在最后一个 wakelock 释放时自动 suspend**，
不再依赖 ROM 的 `system_suspend` 服务：

```bash
adb shell su -c 'echo mem > /sys/power/autosleep'
adb shell su -c 'cat /sys/power/autosleep'     # 期望输出 mem
```

验证是否真的睡了：

```bash
adb shell su -c 'cat /sys/power/suspend_stats/success'   # 数字应持续增长
adb shell su -c 'cat /proc/wakelocks | head'            # 或 dumpsys power
dmesg | grep -i -E 'PM: suspend|Suspended for'
```

如果 `suspend_stats/fail` 在涨，`dmesg` 里会给出失败原因（常见是某个驱动 `-EBUSY`），
把那段贴出来就能定位到具体 wakelock/driver。

## 3. 本次内核相对原厂配置的全部差异

除 KSU/SUSFS 外，只有这些（全部是配置项，不改源码）：

| 选项 | 原厂 | 现在 | 目的 |
| --- | --- | --- | --- |
| `CONFIG_PM_AUTOSLEEP` | n | **y** | 熄屏自动 suspend |
| `CONFIG_TCP_CONG_ADVANCED` / `BBR` / `DEFAULT_BBR` | n | **y** | 网络吞吐/延迟 |
| `CONFIG_NET_SCH_FQ` / `FQ_CODEL` / `PIE` | n | **y** | 队列调度 |
| `CONFIG_IOSCHED_BFQ` | n | **y** | 可选 IO 调度器（默认仍 CFQ） |
| `CONFIG_SCHED_DEBUG` | y | **n** | 去掉调度器调试开销 |
| `CONFIG_CRYPTO_LZ4HC` | n | **y** | zram 可选 lz4hc |
