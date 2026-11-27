# 交接说明

最后更新：2026-11-27 19:30

## 一句话现状

内核已刷入并验证（root、性能项、kallsyms 全部正常）；管理器已去特征、`Root Managers` 检测已消除；**`Native Root` 那条 Danger 仍在**，休眠门控和电池显示未做。

## 设备当前状态

| 项 | 值 |
|---|---|
| 已刷内核 | `boot_a` = `4.14.180-perf` #21（`Fri Nov 27 10:51:48`），带 BBR/fq_codel/BFQ，`/proc/kallsyms` = `-r--------` |
| 槽位 | `_a`，bootloader `unlocked: yes` |
| KSU | 树内 ReSukiSU/BakaSU 系，built-in，UAPI `35286/6` |
| 管理器 | `com.quietforest.systemservice`，label `Baka`，sha256 `c7d132e9…`，签名已授权（`.dynamic_manager`，重启持久） |
| 模块 | 15 目录（管理器计 14，`TA_utl` 缺 `module.prop`） |
| 超级用户 | 3 |
| SELinux | Enforcing |
| autosleep | `mem`（仅回显，**未 arm，不会挂起也不会闪黑**） |

回滚：`fastboot flash boot_a nabu/rom/boot.img`（ROM 包里的原厂 boot）

## 已完成（有真机证据）

### 内核
- `su -c id -u` → `0`；`getenforce` → `Enforcing`
- `/proc/kallsyms` 由 `0444` 改为 `0400`，实测 `-r--------`
- `tcp_congestion_control = bbr`
- 刷入后重启仍生效

### 管理器去特征（`Root Managers` 卡片已消失）

逐项对照实验，每步真机验证：

| 锚点 | 消除方式 |
|---|---|
| `native payload` | `libksud.so` → `libsyshelper.so`，同步改 `KsuCli.getKsuDaemonPath`、`AppZygotePreload`、`DynamicManagerRepository`、`jni.c` 的 argv[0] |
| `label` | `BakaSU` → `Baka`（实测 `BakaSU` 命中、`Baka` 不命中） |
| `launcher class` | `MainActivity` → `SystemActivity` |
| `zygote preload` | 移除 manifest 的 `android:zygotePreloadName` |
| `application class` | 删除自定义 Application，初始化移到 `AppInitProvider` |

副作用：移除 zygote preload 后 **LKM 模式的 magica/late-load 不可用**（内置内核模式不受影响）；若将来切 LKM 需恢复该属性，代价是锚点回来。

### 隐藏配置

- SUSFS `/data/adb/ksu/.susfs.json`：`uname` 伪装成 `4.14.180-moon-os3-ga5805c039`、`sus_path`（su/ksu/modules/lspd）、`sus_kstat`、`logging=false`
- 禁用 `mountify`（与 `sus_mount` 重复）、`Yurikey`（与 `tricky_store` 重复供 keybox）
- 清理 `/data/adb` 的 Magisk 残留
- `/data/local/tmp` 从 82 MB / 124 文件清到 7.5 K（备份 `/sdcard/Download/local-tmp-backup-20261127.tgz`）

## 未完成

| 项 | 方案 | 验收 |
|---|---|---|
| **`Native Root` Danger** | 构成 `28 paths · 6 proc entries · 32 cgroup dirs · 3 kernel sources · 5 props`，`Kernel=Clean / Runtime=Limited`。清 `/data/local/tmp` 后仍在 → 主要来自内核侧（疑似 prctl 探测）。先跑非 root 探针枚举 `/proc`、cgroup、getprop、探测 prctl，再决定改内核还是补 SUSFS | 卡片消失或降级 |
| **休眠门控** | 用树里已有 `msm_drm_notifier`：熄屏 `POWERDOWN`→`pm_autosleep_set_state(PM_SUSPEND_MEM)`，亮屏 `UNBLANK`→`PM_SUSPEND_ON`。新增 .c 用 `git apply` 打新文件，Makefile 用 `sed` 插入 | 亮屏 3 分钟不闪黑且 `suspend_stats` 不增长；**拔线**熄屏 2-3 分钟 `success` 增长 |
| **电池容量显示** | 内核侧正常（`charge_full=8,688,000` / `design=8,720,000`），问题在 `framework-res.apk` 的 `power_profile.xml` 里 `battery.capacity=1000`。**禁用 bind mount**（试过导致 zygote 崩溃），要做 systemless 模块覆盖 | 设置里显示 8720 |
| **seccomp** | 内核已有 `SECCOMP` + `SECCOMP_FILTER`；管理器显示"未启用"指的是 KSU 侧特性开关（`/data/adb/ksu/.feature_config`），改它需完整回归。与 `Native Root` 大概率无关 | 管理器显示已启用且 `su`/模块无回归 |
| **省电配置** | 逐项加、逐项看 `reference-config.diff` 确认落地 | 不做"看起来有用"的项 |

## 关键结论与坑

1. **`autosleep` 只设源码变量不会挂起**，必须 `pm_autosleep_set_state()`。
2. **无条件 arm 会亮屏闪黑**：该 ROM 亮屏时不持有 wakelock，autosleep 会一直强制挂起。实测 `suspend entry=122 / success=11 / fail=50`，单次真实休眠 2 分 21 秒，唤醒源为 `typec-cc-state-change` / `usbin-uv` / `ssusb`。`fail=50`、`alarmtimer -16(EBUSY)` 是**正常否决**，不是故障。所以 README 里"deep suspend verified"只对一半，必须补"亮屏也会睡"这个前提。
3. **KSU 只能用同系管理器**：官方 v0.9.5 → 无 `su`；KernelSU-Next → 报"只支持 GKI"。SUSFS 与 SU 授权无关。
4. **改包名不足以躲 manager 检测**：检测按 APK 内容特征匹配，5 类 anchors 要逐项清。
5. **ROM 内嵌 `.config` 不可信**：`IKCFG` 里写 `-perf`、无 `CONFIG_KSU`，与二进制（`-moon-os3` 带 KSU）矛盾，作者用命令行覆盖了 `LOCALVERSION`。判断 KSU 来源要靠行为验证。
6. **`sed` 改源码必须加 `grep` 断言**：kallsyms 那次没匹配却静默成功，白等一轮。另外注意内核构建用的是 workflow 所在分支的文件。
7. **检测器的 `TEE` 卡是 Info**，属设备完整性体检正常，与 root 无关，不用管。

## 红线

- 构建运行中 **不要 push**（`concurrency: cancel-in-progress` 会取消构建）；push 前先 `ghapi GET "/repos/xinya28/nabu-kernel/actions/runs?per_page=3"` 确认无 `in_progress`
- 验证一律先 `fastboot boot`，确认后再刷 `boot_a`
- 调试休眠**必须拔数据线**（USB 持唤醒源）
- 不要长期用 `adb shell su`（会把 `u:r:ksu:s0` 暴露给检测采样）
- 改系统 APK 不要用 bind mount
- 每次只改一个变量，改完立刻重测对比，避免无法归因

## 环境

- 仓库 `D:\AppData\DSH_WorkSpace\nabu-kernel-ci`，远程 `github.com/xinya28/nabu-kernel`
- 代理 `127.0.0.1:7897`；git 需 `-c http.sslBackend=openssl`；push 用 token URL
- 工具：`gh/ghapi.js`（API）、`gh/download.js`（下载，跟随即重定向）
- 设备：`adb` / `fastboot` 在 PATH；**PowerShell 处理含引号/管道/中文的命令易错，脚本要 push 到 `/data/local/tmp` 再 `su -c sh` 执行**
- 静态编译 ARM64：`D:\AppData\DSH_WorkSpace\ndk\android-ndk-r29\...\aarch64-linux-android21-clang.cmd`，用 `-static -fPIE -pie`

## 文件地图

```
.github/workflows/build.yml     内核构建（perf_overlay / autosleep_default / ksu_source）
.github/workflows/build-manager.yml  管理器构建（package_name / app_name / upstream_ref）
configs/perf.fragment           性能选项（BBR/fq_codel/BFQ/KPROBES）
configs/suspend.fragment        仅 CONFIG_PM_AUTOSLEEP
patches/0001-autosleep-default-mem.patch
tools/repack_boot.js            替换 boot.img 内核（header v3，往返字节校验）
manager-repack/                 keystore、libksud-arm64.so、AppInitProvider.kt、patch_manifest.py
docs/BATTERY_SUSPEND.md         电池与休眠分析（需补"亮屏也会睡"的前提）
```

## 自动任务

- `schedule-629bdb31`：每 45 分钟，专攻 `Native Root` 检测（活跃，20:00 起）
- `schedule-7c8cfb19`：内核/省电收尾（**已暂停**，避免与上面抢构建和 adb）
