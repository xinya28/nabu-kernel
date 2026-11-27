# nabu kernel builds — Xiaomi Pad 5 (nabu / SM8150-AC)

4.14.180 内核与 BakaSU 管理器的构建配方。本仓库**不含**内核源码和管理器源码，
两个 GitHub Actions workflow 在运行时拉取上游、打补丁、出包。

## build.yml — 内核

| 项 | 值 |
|---|---|
| 源码 | `PerezChilli/android_kernel_xiaomi_nabu`，默认分支 `nabu-w-oss-bks` |
| 工具链 | LLVM / Clang + LLD 20.1.8 |
| 构建入口 | `kernel/recovery/scripts/build-recovery.sh` → `out/arch/arm64/boot/Image.gz-dtb` |
| 产物 | AnyKernel3 zip、裸 `Image`、`SHA256SUMS`、`reference-config.diff` |
| 输入 | `source_branch`、`localversion`（默认 `-perf`）、`perf_overlay`、`autosleep_default`、`ksu_source`、`ksu_version` |

构建时的改动只有四处：

1. `patches/0001-autosleep-default-mem.patch` — `autosleep_state` 初值改为 `PM_SUSPEND_MEM`；
2. `patches/0002-autosleep-screen-gate.patch` — 新增 `kernel/power/nabu_autosleep_gate.c`，
   由 Makefile 追加编译项；
3. `configs/perf.fragment` / `configs/suspend.fragment` — 追加到
   `recovery/profile-reference.config`，再 `olddefconfig`；
4. `/proc/kallsyms` 0444 → 0400。

## build-manager.yml — SU 管理器

| 项 | 值 |
|---|---|
| 源码 | `Baka-SU/BakaSU`，默认 commit `cac1e793`（KSU uapi 6） |
| 产物 | 改包名/改 label、去管理器特征、`libksud.so` → `libsyshelper.so` 的 APK |
| 签名 | `manager-repack/ksu-manager.jks` 固定证书，只签 v2 |
| 输入 | `package_name`、`app_name`、`upstream_ref` |

## 两条硬约束（来自代码）

1. 内核 `KernelSU/kernel/manager/apk_sign.c` 只接受**恰好一个 v2 block**：带 v1
   （`META-INF/MANIFEST.MF`）或任何其他 block id（含 v3）的 APK 直接判非法。
2. `/sys/power/autosleep` 只由 `CONFIG_PM_AUTOSLEEP=y` 提供，而该选项只在
   `configs/suspend.fragment` 里——`autosleep_default=false` 的构建没有这个节点。
   另外 `autosleep_state = PM_SUSPEND_MEM` 的初值本身不会排队挂起工作，必须经
   `pm_autosleep_set_state()`。

## 目录

```
.github/workflows/build.yml          内核构建
.github/workflows/build-manager.yml  管理器构建
configs/perf.fragment                性能选项（BBR / fq_codel / BFQ / KPROBES）
configs/suspend.fragment             CONFIG_PM_AUTOSLEEP
patches/                             两个 autosleep 补丁
scripts/pack-anykernel.sh            Image → AnyKernel3 zip
tools/repack_boot.js                 替换 boot.img 内核（header v3）
manager-repack/                      管理器改包素材（keystore、ksud、Provider、manifest 补丁）
```

## 许可

本仓库的 CI 脚本、配置片段与补丁以 GPL-2.0-only 发布（见 `LICENSE`）；
内核与管理器源码版权归各自作者所有。
