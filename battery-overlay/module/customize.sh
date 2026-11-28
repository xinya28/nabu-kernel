#!/system/bin/sh
# Nothing to configure at install time: post-fs-data.sh overlays the prebuilt
# static RRO APK onto /product/overlay on every boot.
ui_print "- 安装静态 RRO: BatteryCapacity.apk（重启后生效）" 2>/dev/null || true
