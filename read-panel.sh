#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# read-panel.sh - report which touch panel variant (and thus which firmware
# blob, fw01 or fw02) your POCO X3 Pro uses. Useful when reporting ghost
# touch fix results.
#
# Run with the phone booted into Android, connected via USB, and USB
# debugging enabled. Tries several sources, most of which work without root.
#
#   panel mapping on vayu (from the device tree and driver):
#     display maker 0x36 / TP vendor 0x46  ->  "nvt+tianma"                 ->  fw01
#     display maker 0x42 / TP vendor 0x53  ->  "nvt+csot" (CSOT / Huaxing)  ->  fw02
set -u
ADB="${ADB:-adb}"
command -v "$ADB" >/dev/null 2>&1 || { echo "adb not found - set ADB=/path/to/adb"; exit 1; }
"$ADB" get-state >/dev/null 2>&1 || { echo "no device found (check cable / USB debugging / authorization)"; exit 1; }

sh() { "$ADB" shell "$@" 2>/dev/null | tr -d '\r'; }

echo "device : $(sh getprop ro.product.device) | $(sh getprop ro.lineage.version)"
echo "kernel : $(sh uname -r)"

verdict() {  # $1 = evidence description, $2 = tianma|csot
  case "$2" in
    tianma) echo "panel  : Tianma (nvt+tianma) -> uses fw01   [$1]";;
    csot)   echo "panel  : CSOT/Huaxing (nvt+csot) -> uses fw02   [$1]";;
  esac
  exit 0
}

# 1) Kernel log via logcat - readable without root on LineageOS, while
#    /proc/cmdline, dmesg and the driver's procfs are SELinux-restricted.
#    The driver logs its firmware choice at boot ("fw_name: j20s_..._fw01.bin")
#    and the logged cmdline carries the DSI display name. Buffer wraps, so
#    this works best within hours of a reboot.
KLOG="$(sh "logcat -d -b kernel 2>/dev/null | grep -E 'fw_name: j20s|dsi_j20s_' | head -4")"
[ -n "$KLOG" ] || KLOG="$(sh "logcat -d 2>/dev/null | grep -E 'fw_name: j20s|dsi_j20s_' | head -4")"
if [ -n "$KLOG" ]; then
  echo "klog   :"; printf '%s\n' "$KLOG" | sed 's/^/         /'
  # The display name is deterministic (maker 36 -> Tianma/fw01, 42 -> CSOT/fw02).
  # Note: nvt_parse_dt logs the fw_name of BOTH DT configs, so a fw_name line
  # only identifies the panel when exactly one of the two appears in the log.
  case "$KLOG" in
    *dsi_j20s_36_*) verdict "display name in kernel log, maker 0x36" tianma;;
    *dsi_j20s_42_*) verdict "display name in kernel log, maker 0x42" csot;;
  esac
  has01=0; has02=0
  case "$KLOG" in *"fw_name: j20s_novatek_ts_fw01"*) has01=1;; esac
  case "$KLOG" in *"fw_name: j20s_novatek_ts_fw02"*) has02=1;; esac
  [ "$has01$has02" = "10" ] && verdict "driver log, only fw01 named" tianma
  [ "$has01$has02" = "01" ] && verdict "driver log, only fw02 named" csot
fi

# 2) Kernel cmdline directly (often SELinux-restricted for shell)
CMDLINE="$(sh cat /proc/cmdline)"
DISP="$(printf '%s' "$CMDLINE" | grep -oE 'dsi_j20s_[0-9a-fx]+_[0-9a-z_]*display' | head -1)"
if [ -n "$DISP" ]; then
  echo "display: $DISP"
  case "$DISP" in
    dsi_j20s_36_*) verdict "display name, maker 0x36" tianma;;
    dsi_j20s_42_*) verdict "display name, maker 0x42" csot;;
  esac
fi

# 3) Touchscreen lockdown info exposed via sysfs (first byte = TP vendor)
LOCK_FILE="$(sh 'find /sys/devices /sys/class -name "*lockdown*" 2>/dev/null | head -1')"
if [ -n "$LOCK_FILE" ]; then
  LOCK="$(sh cat "$LOCK_FILE")"
  echo "lockdown ($LOCK_FILE): $LOCK"
  case "$LOCK" in
    46*|0x46*) verdict "lockdown TP vendor 0x46" tianma;;
    53*|0x53*) verdict "lockdown TP vendor 0x53" csot;;
  esac
fi

# 4) Rooted fallback: the driver logs its firmware choice in dmesg
NVT="$(sh 'su -c dmesg 2>/dev/null | grep -iE "nvt|novatek" | grep -iE "fw_name|firmware|lockdown|panel" | tail -5')"
if [ -n "$NVT" ]; then
  echo "dmesg  :"; printf '%s\n' "$NVT"
  case "$NVT" in
    *fw01*) verdict "dmesg fw_name" tianma;;
    *fw02*) verdict "dmesg fw_name" csot;;
  esac
fi

echo "could not determine the panel automatically."
echo "Manual route (rooted): su -c 'dmesg | grep -i nvt' right after boot - look"
echo "for the selected fw name (j20s_novatek_ts_fw01/fw02) or lockdown info."
exit 2
