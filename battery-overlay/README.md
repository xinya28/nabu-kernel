# battery-overlay

Android 16 / HyperOS 3 on Xiaomi Pad 5 (nabu) keeps reporting a **1000 mAh**
battery because `framework-res.apk` ships the AOSP default power profile:

```
res/xml/power_profile.xml: <item name="battery.capacity">1000</item>
```

The real cell is 8720 mAh (`charge_full_design = 8,720,000 µAh`). This directory
builds a **static runtime resource overlay** for that single XML resource and
packs it into a KSU module. `framework-res.apk` is never touched.

## Layout

| path | purpose |
|---|---|
| `res/xml/power_profile.xml` | device power profile, only `battery.capacity` changed to 8720 |
| `AndroidManifest.xml` | RRO manifest: `targetPackage="android"`, `isStatic="true"`, `hasCode="false"` |
| `framework-res-stub.apk` | 2 MB `resources.arsc`-only stub of the device's framework-res, used as `aapt2 -I` |
| `module/` | KSU module payload (`module.prop`, `customize.sh`, `post-fs-data.sh`, `skip_mount`) |

## Why the stub

`<overlay android:targetPackage=... android:isStatic=...>` uses private framework
attributes (`0x01010021`, `0x0101055a`). They are not part of the public
`android.jar`, so linking against `platforms/android-XX/android.jar` leaves the
`<overlay>` tag without usable attribute ids and PackageManager silently ignores
the overlay. The stub is the device's own resource table, which has them.

## Why post-fs-data.sh mounts /product/overlay

The ROM has no `/system/overlay`, and KernelSU's module mount cannot create new
top-level directories on the read-only `/system`. `/product/overlay` exists, is
scanned by PackageManager for preloaded overlays, and is already a mount point,
so the module stacks a read-only overlayfs on it:

```
mount -t overlay overlay -o lowerdir=$MODDIR/overlay:/product/overlay /product/overlay
```

The ROM's own overlays stay visible in the lower layer; only
`BatteryCapacity.apk` is added. This runs before `system_server` starts.

## Preloaded overlay vs. `pm install`

Installing the APK with `pm install` fails by design:

```
INSTALL_FAILED_INTERNAL_ERROR: Overlay com.nabu.batterycap and target android
signed with different certificates, and the overlay lacks
<overlay android:targetName>
```

`InstallPackageHelper.assertOverlayIsValid` only applies that certificate check
to non-preloaded overlays; a preloaded (system partition) overlay skips it, so
the module path works while a user install does not.

## Build

`.github/workflows/build-battery-overlay.yml` (`workflow_dispatch`, own
concurrency group `battery-overlay`) builds, signs with
`manager-repack/ksu-manager.jks` and uploads the APK plus the module zip.

## Roll back

Delete `/data/adb/modules/battery_capacity_fix` and reboot: the overlayfs mount
disappears with the module, `/product/overlay` returns to the ROM contents and
the reported capacity goes back to 1000 mAh.
