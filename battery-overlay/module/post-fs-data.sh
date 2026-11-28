#!/system/bin/sh
# Static RRO delivery.
#
# The tablet's /system has no /system/overlay, and KernelSU's own module mount
# cannot create new top-level directories there. The ROM does have a product
# overlay directory (/product/overlay) which PackageManager scans for preloaded
# RROs and which is itself a mount point, so it can be overlaid. Layering our
# single APK on top of it is enough: the ROM's own overlays stay in the lower
# layer and keep working, while BatteryCapacity.apk becomes visible to
# PackageManager before system_server starts.
MODDIR=${0%/*}
[ -z "$MODDIR" ] && MODDIR=/data/adb/modules/battery_capacity_fix

# Already mounted (e.g. manual re-run of the script)?
if [ -e /product/overlay/BatteryCapacity.apk ]; then
  exit 0
fi

mount -t overlay overlay \
  -o "lowerdir=$MODDIR/overlay:/product/overlay" \
  /product/overlay

# Make sure the mount is usable even if the kernel picked read-only overlay.
chmod 0644 /product/overlay/BatteryCapacity.apk 2>/dev/null
