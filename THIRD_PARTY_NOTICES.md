# 第三方组件与许可声明

本项目（仓库根目录的 CI 配方、配置片段、补丁与脚本）以 **GPL-2.0-only** 发布，全文见 [LICENSE](LICENSE)。

仓库本身**不包含内核源码**，构建时由 GitHub Actions 从上游仓库拉取。下列组件的著作权归各自作者所有，
其许可条款独立于本项目；构建产物（`Image`、`boot.img`、AnyKernel3 zip）作为上游作品的衍生作品，
一并受相应许可约束。

## 内核源码

| 项目 | 许可 | 用途 |
|---|---|---|
| [Linux kernel](https://www.kernel.org/) | GPL-2.0 | 基础内核 |
| [PerezChilli/android_kernel_xiaomi_nabu](https://github.com/PerezChilli/android_kernel_xiaomi_nabu) | GPL-2.0 | 本项目使用的 nabu 内核树（分支 `nabu-w-oss-bks`） |

构建产物对应源码的获取方式：上述上游仓库 + 本仓库 `patches/` 与 `configs/` 中的补丁和配置片段，
按 [README](README.md) 记录的输入参数即可复现。GPL-2.0 第 3 条要求的源码提供义务由这两部分共同满足。

## KernelSU 与管理器

| 项目 | 许可 | 用途 |
|---|---|---|
| [tiann/KernelSU](https://github.com/tiann/KernelSU) | GPL-2.0 | KernelSU 上游 |
| [Baka-SU/BakaSU](https://github.com/Baka-SU/BakaSU) | GPL-2.0 | 内核内置的 KernelSU 下游实现，以及配套管理器 APK |

管理器的改包名 / 去特征版本由本项目的 CI（`.github/workflows/build-manager.yml`）在上游源码基础上
自动化修改并重新签名，其衍生作品同样受 GPL-2.0 约束。

## 刷写与打包工具

| 项目 | 许可 | 用途 |
|---|---|---|
| [AnyKernel3](https://github.com/osm0sis/AnyKernel3) | 见上游仓库 | 生成可刷写的 AnyKernel3 zip |
| `tools/repack_boot.js` | GPL-2.0 | 本项目自写，用于替换 `boot.img`（header v3）中的内核 |

## 其他

- Android 是 Google LLC 的商标。本项目与小米、Google、KernelSU 上游维护者均无隶属关系。
- 本项目仅供个人设备研究与自用；刷写自定义内核可能导致设备无法启动、数据丢失或保修失效，风险自负。
