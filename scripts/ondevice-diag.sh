#!/system/bin/sh
# nabu 电池 / 休眠 现场取证脚本
# 用法（电脑端）：
#   adb push scripts/ondevice-diag.sh /data/local/tmp/
#   adb shell su -c sh /data/local/tmp/ondevice-diag.sh > diag.txt
# 输出全部是只读命令，不改任何状态。

echo "===== 0. 内核与系统 ====="
uname -a
cat /proc/cmdline
getprop ro.build.version.release
getprop ro.build.version.incremental
getprop ro.product.device
getprop ro.product.vendor.device
getprop | grep -i -E 'battery|power|charge' | head -30

echo
echo "===== 1. power_supply 全量 uevent ====="
for d in /sys/class/power_supply/*; do
  [ -d "$d" ] || continue
  echo "--- $d"
  cat "$d/uevent" 2>/dev/null
done

echo
echo "===== 2. 关键节点（battery / bms / usb / pc_port） ====="
for n in battery bms usb pc_port; do
  d=/sys/class/power_supply/$n
  [ -d "$d" ] || continue
  echo "--- $n"
  for f in capacity capacity_level status health present voltage_now current_now \
           charge_counter charge_full charge_full_design cycle_count temp \
           technology system_temp_level charge_type constant_charge_current_max; do
    [ -r "$d/$f" ] && echo "  $f = $(cat "$d/$f" 2>/dev/null)"
  done
done

echo
echo "===== 3. FG / charger dmesg ====="
dmesg | grep -i -E 'fg_gen4|fg-gen4|qpnp-fg|smb5|batt|charger|capacity|profile' | tail -120

echo
echo "===== 4. 电源状态 ====="
echo "state          : $(cat /sys/power/state 2>/dev/null)"
echo "autosleep      : $(cat /sys/power/autosleep 2>/dev/null || echo '(无此节点)')"
echo "wakeup_count   : $(cat /sys/power/wakeup_count 2>/dev/null)"
cat /sys/power/suspend_stats/* 2>/dev/null

echo
echo "===== 5. wakelock 排行 ====="
if [ -r /sys/kernel/debug/wakeup_sources ]; then
  head -1 /sys/kernel/debug/wakeup_sources
  tail -n +2 /sys/kernel/debug/wakeup_sources | sort -k6 -nr | head -20
elif [ -r /proc/wakelocks ]; then
  head -3 /proc/wakelocks
  tail -n +4 /proc/wakelocks | sort -k7 -nr | head -20
else
  echo "(无 wakeup_sources / proc/wakelocks)"
fi
dumpsys power 2>/dev/null | grep -i -E 'Wake Locks|mWakefulness|mHoldingDisplay|mHoldingWakeLockSuspendBlocker|Display Power' | head -20

echo
echo "===== 6. 最近的 suspend/resume 记录 ====="
dmesg | grep -i -E 'PM: suspend|Suspended for|suspend entry|suspend exit|Freezing' | tail -40

echo
echo "===== done ====="
