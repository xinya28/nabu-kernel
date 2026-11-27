# manager-repack — 改包名/去指纹管理器构建素材

这个目录配合 `.github/workflows/build-manager.yml`，把上游
[Baka-SU/BakaSU](https://github.com/Baka-SU/BakaSU) 的管理器源码重新构建成一个
**包名随机、签名稳定、且不命中 Duck Detector "Root Managers" 特征**的 APK，
同时保留 su 授权、模块管理与 SuSFS 功能。

## 最终交付（已真机验证）

| 项 | 值 |
|---|---|
| applicationId | `com.quietforest.systemservice`（workflow 输入 `package_name`） |
| launcher label | `Baka`（workflow 输入 `app_name`） |
| 版本 | v4.2.0-rc3 (35286)，上游 commit `cac1e793`，KSU uapi 6 |
| 签名证书 | `0x37d` (893 B)，sha256 `ca3e17aed890c399991ce1bfcccba7925743728c70ebbaf7cc8d03f5ee9074e2` |
| APK | `ksu-manager_com.quietforest.systemservice_35286.apk`，sha256 `c7d132e98aab050f87a1b0c48d8971d79efa7923296cf96d3941313c691bb696` |

设备上：`su -c id` 为 root、首页「工作中 Built-in」、3 个超级用户 / 14 个模块、
SuSFS 页正常；Duck Detector 的 **Root Managers 卡片已消失**（`Native Root` 卡片仍为
Danger，属于内核层 `ksu_driver` 检测，改 APK 无法消除）。

## 文件

| 文件 | 说明 |
|---|---|
| `ksu-manager.jks` | 固定签名密钥库（PKCS12，alias `ksu-manager`，RSA 2048，30 年）。 |
| `libksud-arm64.so` | 从官方 35286 管理器取出的 `lib/arm64-v8a/libksud.so`，构建时以 `libsyshelper.so` 注入 APK。内核侧 ksud 与它同源；管理器没有它就无法起 root shell。 |
| `AppInitProvider.kt` | 代替被删除的自定义 Application 类：在第一个 Activity 之前完成 Koin 与 `InitializeApplicationUseCase` 初始化。 |
| `patch_manifest.py` | 构建时修改 AndroidManifest：删除 `android:name=".Sys"`，注册 `AppInitProvider`。 |

## 这个 workflow 改了什么（去指纹链路）

Duck Detector 对“root 管理器”的判定由 5 类 anchors 组成，逐项消除过程：

| anchor | 处理方式 | 结果 |
|---|---|---|
| 包名 | `applicationId` 改为输入参数（默认 `com.quietforest.systemservice`） | 旧包名不再命中 |
| `label` | 应用名改为 `Baka`（`BakaSU` 会被命中） | label 锚点消失 |
| `native payload` (`libksud.so`) | 改名为 `libsyshelper.so`，同步改 `KsuCli`、`AppZygotePreload`、`DynamicManagerRepository`、`jni.c` 的引用 | payload 锚点消失 |
| `launcher class` | `MainActivity` → `SystemActivity`（含 manifest、activity-alias、快捷方式、硬编码 ComponentName） | launcher 锚点消失 |
| `zygote preload` | 移除 manifest 的 `android:zygotePreloadName`（内置内核模式不需要 LKM 的 app_zygote） | 锚点消失 |
| `application class` | 删除自定义 Application 类，初始化移入 `AppInitProvider`（ContentProvider） | 锚点消失，Root Managers 卡片消失 |

⚠️ 移除 zygote preload 后，LKM 模式的 magica/late-load 路径不可用；内置内核模式不受影响。

## 为什么把私钥提交进仓库

内核的动态管理器只比对**证书**（长度 + DER 的 SHA-256），不认包名。固定 keystore
才能做到“授权一次、重建/重启后继续有效”。密码写在 workflow 的 `env` 里。

⚠️ **该 keystore 仅供此用途。** 私钥是公开的，任何人都能签出同一证书的 APK；
不要用它签任何其他东西。这是个人自用项目的取舍，不要照搬到正式发行。

## 构建与签名约束

* 内核只接受单个 v2 签名块：带 v1（`META-INF/MANIFEST.MF`）或 v3 block 的 APK 会被
  `kernel/manager/apk_sign.c` 判为非法。workflow 会删 v1 残留并用 `apksigner`
  以 `--v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled false`
  重签。
* 版本号来自上游 git 历史：`versionCode = 30000 + git rev-list --count HEAD + 700`，
  `versionName = git describe --tags --always --abbrev=0`。构建 commit 必须与内核
  uapi 匹配（`cac1e793`，uapi 6，versionCode 35286），不要用 `v4.2.0-rc3` tag（uapi 4）。
* workflow 使用独立 `concurrency: group: manager-repack`，与内核构建的
  `${{ github.workflow }}-${{ github.ref }}`（`cancel-in-progress: true`）无关。

## 设备侧授权（一次，重启有效）

`ksud` 把配置写到 `/data/adb/ksu/.dynamic_manager`（JSON：size + hash），每次开机由
`dynamic_manager::booted_load()` 重新灌进内核：

```sh
su -c '/data/adb/ksu/bin/ksud kernel dynamic-manager set-apk \
  "$(pm path com.quietforest.systemservice | head -n1 | cut -d: -f2)"'
su -c '/data/adb/ksu/bin/ksud kernel dynamic-manager get --internal true'
```

也可以手动指定：

```sh
su -c '/data/adb/ksu/bin/ksud kernel dynamic-manager set 0x37d \
  ca3e17aed890c399991ce1bfcccba7925743728c70ebbaf7cc8d03f5ee9074e2'
```

设置成功后内核会同步重扫 `/data/app`，把该证书对应的包注册成 manager。
