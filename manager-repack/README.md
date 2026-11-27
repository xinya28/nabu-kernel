# manager-repack

`build-manager.yml` 用的改包素材，不参与内核构建。

| 文件 | 用途 |
|---|---|
| `ksu-manager.jks` | 固定签名密钥库（PKCS12，alias `ksu-manager`），密码在 workflow 的 `env` 里 |
| `libksud-arm64.so` | ksud 可执行文件（ELF64 / aarch64），构建时以 `libsyshelper.so` 注入 APK |
| `AppInitProvider.kt` | 替代被删除的自定义 Application：在首个 Activity 之前完成 Koin 与 `InitializeApplicationUseCase` 初始化 |
| `patch_manifest.py` | 删除 `android:name=".Sys"`，注册 `AppInitProvider` |

⚠️ 私钥是公开的，只用于这个管理器：内核的动态管理器只比对证书的 size + SHA-256，
固定证书才能让授权在重建 APK / 重启后继续有效。不要用它签任何其他 APK。

## 签名约束

内核只接受单个 v2 block（见 `KernelSU/kernel/manager/apk_sign.c`），v1 与 v3 都会被判非法。
workflow 因此会删掉 `META-INF` 里的 v1 残留，再用 `apksigner` 以
`--v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled false` 重签。

## 设备侧授权（一次，重启有效）

```sh
su -c '/data/adb/ksu/bin/ksud kernel dynamic-manager set-apk <apk 路径>'
su -c '/data/adb/ksu/bin/ksud kernel dynamic-manager get --internal true'
```
