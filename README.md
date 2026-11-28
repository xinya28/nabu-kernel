<div align="center">

# nabu-HyperOS3-A16 · su-manager

### 小米平板 5（nabu）HyperOS 3 / Android 16 的 KernelSU 管理器改包流水线

![powered by dsh](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)
![device](https://img.shields.io/badge/device-nabu_%2F_Xiaomi_Pad_5-orange?style=flat-square)
![source](https://img.shields.io/badge/source-HyperOS_3_%2F_Android_16-blue?style=flat-square)
![CI](https://img.shields.io/badge/CI-GitHub_Actions-green?style=flat-square)
![license](https://img.shields.io/badge/license-GPL--2.0--only-orange?style=flat-square)

</div>

本仓库是 `nabu-HyperOS3-A16` 的**管理器分支**，只存放 KernelSU 管理器的改包名 / 去特征流水线
（`.github/workflows/build-manager.yml` 与 `manager-repack/`），不包含内核构建所需的任何内容。
内核构建配方见同仓库的 `kernel` 分支。

## 为什么需要改包

内核内置的是 BakaSU / ReSukiSU 系实现（KSU uapi 6），官方 KernelSU v0.9.5 在非 GKI 内核下不提供
`su`，KernelSU-Next 会直接提示"只支持 GKI 内核"，所以管理器必须用同系上游。

但上游管理器 APK 带有 Duck Detector 等原生检测会抓取的固定指纹。本流水线在上游源码基础上自动改掉这些
特征，同时保持 `su`、模块、SuSFS 功能不变：

| 特征 | 改法 |
|---|---|
| `applicationId` | 由输入决定，默认 `com.quietforest.systemservice` |
| 桌面名称 | 由输入决定，默认 `Baka` |
| 内置 ksud 库名 | `libksud.so` → `libsyshelper.so`，`KsuCli` / `AppZygotePreload` / `DynamicManagerRepository` / `jni.c` 同步改 |
| Application 类 | 删除自定义 Application，初始化搬进首个 Activity 之前运行的 `AppInitProvider` |
| zygote preload | 删除仅 LKM 模式使用的 `android:zygotePreloadName` 属性（内置内核模式不受影响） |
| 启动类名 | `MainActivity` → `SystemActivity`，文件与清单同步改名 |

## 签名约束（重要）

内核用自己的 v2 block 解析器校验管理器 APK：**只接受单个 v2 block**，出现 v1
（`META-INF/MANIFEST.MF`）或 v3 签名块一律判为非法。因此 Gradle 产物会被删掉 v1 残留，再用
`apksigner` 以 `--v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled false` 重签。

签名密钥固定在 `manager-repack/ksu-manager.jks`（PKCS12，alias `ksu-manager`）。内核的动态管理器
只比对证书的 size + SHA-256，所以固定证书才能让授权在重建 APK、重启后继续有效。
**该私钥是公开的个人项目密钥，只能用于这个管理器，不要拿它签任何其他 APK。**

## 构建

Actions 页面手动 `workflow_dispatch` 运行 `build-manager`，输入：

| 输入 | 默认值 | 说明 |
|---|---|---|
| `package_name` | `com.quietforest.systemservice` | 改包后的 applicationId |
| `app_name` | `Baka` | 桌面显示名 |
| `upstream_ref` | `cac1e793` | BakaSU 提交/标签，必须与内核的 KSU uapi（6）匹配 |

单次构建约 15-25 分钟，产物为 `dist/ksu-manager_<package>_<versionCode>.apk`（Actions artifact，保留 30 天）。

`concurrency` 使用独立分组 `manager-repack` 且 `cancel-in-progress: false`，不会取消内核构建
（`build.yml` 的分组是 `cancel-in-progress: true`）。

## 设备侧授权

改包后的管理器不会被内核自动信任，需要一次性授权（重启后仍有效）：

```sh
su -c '/data/adb/ksu/bin/ksud kernel dynamic-manager set-apk <apk 路径>'
su -c '/data/adb/ksu/bin/ksud kernel dynamic-manager get --internal true'
```

授权记录保存在 `/data/adb/ksu/.dynamic_manager`，证书不变则重建 APK 后无需重新授权。

## 目录结构

```
.github/workflows/build-manager.yml   改包 / 去特征 / 重签流水线
manager-repack/ksu-manager.jks        固定签名密钥库
manager-repack/libksud-arm64.so       ksud 可执行文件，注入为 libsyshelper.so
manager-repack/AppInitProvider.kt     替代被删除的 Application 初始化
manager-repack/patch_manifest.py      清单改写脚本
```

## 许可与致谢

本项目以 **GPL-2.0-only** 发布，全文见 [LICENSE](LICENSE)；第三方组件见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

管理器 APK 是 [Baka-SU/BakaSU](https://github.com/Baka-SU/BakaSU) 的衍生作品，遵循 GPL-2.0；
上游 KernelSU 见 [tiann/KernelSU](https://github.com/tiann/KernelSU)。

## 免责声明

改包与 root 相关操作存在风险，可能导致设备无法启动或数据丢失。本项目仅供个人设备研究与自用，
与小米、Google、KernelSU 上游维护者均无隶属关系。
