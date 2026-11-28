<div align="center">

# nabu-HyperOS3-A16

### 小米平板 5（nabu / SM8150-AC）· HyperOS 3 / Android 16 · 4.14.180 内核

![powered by dsh](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)
![device](https://img.shields.io/badge/device-nabu_%2F_Xiaomi_Pad_5-orange?style=flat-square)
![source](https://img.shields.io/badge/source-HyperOS_3_%2F_Android_16-blue?style=flat-square)
![kernel](https://img.shields.io/badge/kernel-4.14.180_%2B_nabu_drivers-blue?style=flat-square)
![CI](https://img.shields.io/badge/CI-GitHub_Actions-green?style=flat-square)
![license](https://img.shields.io/badge/license-GPL--2.0--only-orange?style=flat-square)

</div>

小米平板 5（nabu）移植版 HyperOS 3 / Android 16 优化。
本仓库只做索引，实际内容按分支划分。

## 分支

| 分支 | 内容 |
|---|---|
| [`kernel`](../../tree/kernel) | 内核构建流程、配置片段、补丁与打包工具 |
| [`su-manager`](../../tree/su-manager) | KernelSU 管理器构建（改包名 / 去特征） |

## 发布

| 产物 | 位置 |
|---|---|
| 内核镜像（boot.img / AnyKernel3 / Image） | [Releases](../../releases) |
| KSU 管理器 APK（原版 / 改包名版） | [Releases](../../releases) |

## 相关仓库

| 仓库 | 用途 |
|---|---|
| [nabu-battery-fix](https://github.com/xinya28/nabu-battery-fix) | 电池容量显示修正（RRO 覆盖 `battery.capacity` → 8720 mAh） |
| [nabu-adb-enable](https://github.com/xinya28/nabu-adb-enable) | ADB 常驻开启 KSU 模块 |
| [nabu-sched-tuning](https://github.com/xinya28/nabu-sched-tuning) | 调度与核心分配固化 KSU 模块（数值来自实测能效曲线） |

## 已知结论

- KernelSU 必须使用同系管理器（ReSukiSU / BakaSU 系，UAPI `35286`），官方 v0.9.5 与 KernelSU-Next 均不匹配
- 熄屏休眠需屏幕状态门控：熄屏才允许挂起，亮屏立即禁止，否则使用中会周期性熄屏
- `/proc/kallsyms` 默认为全局可读，是内核被识别的指纹，已在构建中收紧为 `0400`

详见 [`kernel`](../../tree/kernel) 分支的 README 与 `docs/`。

## 许可

[GPL-2.0-only](LICENSE) · 第三方组件与源码获取方式见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
