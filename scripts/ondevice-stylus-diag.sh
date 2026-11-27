#!/system/bin/sh
# 手写笔 / 蓝牙 / 音频 断流取证脚本
# 用法：
#   adb push scripts/ondevice-stylus-diag.sh /data/local/tmp/
#   adb shell su -c sh /data/local/tmp/ondevice-stylus-diag.sh > stylus-diag.txt
# 采样分两段：A=静置不碰笔，B=持续用笔写字（脚本会提示你开始写）

SAMPLE=8

snap() {
  tag="$1"
  echo "===== [$tag] $(date) ====="
  echo "--- uptime/load"
  cat /proc/loadavg
  echo "--- /proc/interrupts"
  cat /proc/interrupts
  echo "--- /proc/stat"
  cat /proc/stat | grep '^cpu'
  echo "--- top -H -n 1"
  top -H -n 1 -m 12 -o %CPU 2>/dev/null | head -20
  echo "--- dmesg tail"
  dmesg | tail -60
  echo "--- audio"
  dumpsys audio 2>/dev/null | grep -i -E 'underrun|glitch|state|track' | head -20
  echo "--- bluetooth"
  dumpsys bluetooth_manager 2>/dev/null | grep -i -E 'state|a2dp|codec|underrun' | head -20
}

echo "########## 阶段 A：静置（不要碰屏幕，等 $SAMPLE 秒） ##########"
snap "A-start"
sleep $SAMPLE
snap "A-end"

echo
echo "########## 阶段 B：现在开始用笔连续写字，持续 $SAMPLE 秒 ##########"
snap "B-start"
sleep $SAMPLE
snap "B-end"

echo
echo "########## 日志里的断流证据 ##########"
logcat -b all -d 2>/dev/null | grep -i -E 'underrun|a2dp|avdt|bt_|bluetooth|audio_hw|glitch|drop' | tail -120
echo "===== done ====="
