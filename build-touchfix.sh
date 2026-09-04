#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# build-touchfix.sh - build a ghost-touch-fixed boot.img for the
# POCO X3 Pro (vayu) on LineageOS.
#
# Rebuilds the LineageOS kernel from the EXACT source revision of your
# installed build, with only the two embedded Novatek touch firmware blobs
# swapped to V12.5.5.0.RJUIDXM prod (a firmware version long used by vayu
# community kernels to address the ghost touch issue), then repacks the
# boot.img you provide with the new kernel. The ramdisk, DTB and boot
# header parameters of your boot.img are reused and verified afterwards.
#
# Reproducibility: official LineageOS kernels embed their git revision in
# the version string (e.g. "-g59220a048d04"); this script extracts that
# from your boot.img and downloads exactly that source revision, so the
# functional kernel source matches your installed build and the intended
# functional change is limited to the two firmware blobs. The rebuilt
# binary can still differ in build metadata and compiler output: it is
# built with the pinned Proton Clang 13 (official builds use AOSP clang)
# and, being built from a tarball, lacks the -g<sha> localversion suffix.
# Toolchain and mkbootimg are pinned to fixed commits below.
#
# Usage:
#   ./build-touchfix.sh <boot.img of your installed LineageOS build> [kernel-ref]
#
#   <boot.img>    the boot image belonging to your INSTALLED nightly, from
#                 https://download.lineageos.org/devices/vayu/builds
#                 (separate file next to the ROM zip of the same date).
#   [kernel-ref]  optional override: a commit sha or branch of
#                 LineageOS/android_kernel_xiaomi_sm8150 to build instead
#                 of the auto-detected revision.
#
# Tested baseline: LineageOS 22.2 nightly 20260816 (kernel 59220a048d04).
#
# Requirements: Linux x86_64, ~8 GB free disk, and:
#   gcc g++ make bc openssl python3 binutils (objcopy/strings) curl tar libssl-dev
set -euo pipefail

# ---- pinned inputs ---------------------------------------------------------
# Toolchain: kdrag0n/proton-clang, master as of 2021-05-22 (clang 13.0.0).
PROTON_REF=9fb011b183fe7e69b04b873ef6533b4b077e3c5e
# AOSP mkbootimg/unpack_bootimg, main as of 2025-03-02.
MKBOOTIMG_REF=d2bb0af5ba6d3198a3e99529c97eda1be0b5a093
# Expected content of the V12.5.5.0.RJUIDXM fix firmware (sha256 of the DECODED .bin):
FW01_SHA=610f3521e3fb384f11f43d49a71e9eb9e8990f0b004d0a7532ec749e2b866334
FW02_SHA=7392a835cca1296f552c613a9678722a5312403950018ff1af27f4adc704cb7e
# ---------------------------------------------------------------------------

BOOT="${1:?Usage: $0 <path to boot.img of your installed LineageOS build> [kernel-ref]}"
KREF_ARG="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# kbuild cannot handle spaces in paths, so all build work happens in a
# space-free cache directory:
W="${XDG_CACHE_HOME:-$HOME/.cache}/vayu-touchfix"
case "$W" in *" "*) echo "build dir contains a space: $W - adjust W in this script"; exit 1;; esac
JOBS="$(nproc)"

BOOT="$(readlink -f "$BOOT")"
OUTDIR="$(pwd)"
[[ -f "$BOOT" ]] || { echo "boot.img not found: $BOOT"; exit 1; }
for t in gcc g++ make bc openssl python3 objcopy strings curl tar; do
  command -v "$t" >/dev/null || { echo "missing tool: $t"; exit 1; }
done
[[ -r /usr/include/openssl/opensslv.h ]] || { echo "libssl-dev is missing (e.g. sudo apt install libssl-dev)"; exit 1; }

mkdir -p "$W"; cd "$W"

echo "== [1/8] Fetching pinned tools (cached in $W after the first run) =="
if [[ ! -f "mkbootimg-$MKBOOTIMG_REF/mkbootimg.py" ]]; then
  mkdir -p "mkbootimg-$MKBOOTIMG_REF"
  curl -fL "https://android.googlesource.com/platform/system/tools/mkbootimg/+archive/$MKBOOTIMG_REF.tar.gz" \
    | tar -xz -C "mkbootimg-$MKBOOTIMG_REF"
fi
MKB="$W/mkbootimg-$MKBOOTIMG_REF"
if [[ ! -x "proton-clang-$PROTON_REF/bin/clang" ]]; then
  curl -fL -o proton-clang.tar.gz "https://codeload.github.com/kdrag0n/proton-clang/tar.gz/$PROTON_REF"
  tar -xzf proton-clang.tar.gz    # extracts to proton-clang-$PROTON_REF/
  rm -f proton-clang.tar.gz
fi
TC="$W/proton-clang-$PROTON_REF/bin"

echo "== [2/8] Unpacking your boot.img and detecting its kernel source revision =="
rm -rf bootimg bootimg-check
ARGS_IN="$(python3 "$MKB/unpack_bootimg.py" --boot_img "$BOOT" --out bootimg --format mkbootimg)"
KVER="$(strings bootimg/kernel | grep -m1 '^Linux version ' || true)"
echo "kernel: ${KVER:-<no version string found>}"
KREF="$(printf '%s' "$KVER" | grep -oE '\-g[0-9a-f]{12,40}' | head -1 | cut -c3- || true)"
if [[ -n "$KREF_ARG" ]]; then
  KREF="$KREF_ARG"
  echo "using kernel ref from command line: $KREF"
elif [[ -n "$KREF" ]]; then
  echo "auto-detected kernel source revision: $KREF"
else
  echo "ERROR: could not detect a git revision in this kernel (no -g<sha> suffix)."
  echo "Use the UNMODIFIED boot.img of your installed official build, or pass a"
  echo "kernel ref explicitly: $0 <boot.img> <commit-or-branch>"
  exit 1
fi

echo "== [3/8] Downloading LineageOS kernel source at $KREF (~200 MB) =="
rm -rf los; mkdir los
curl -fL "https://codeload.github.com/LineageOS/android_kernel_xiaomi_sm8150/tar.gz/$KREF" \
  | tar -xz -C los --strip-components=1
for n in 01 02; do
  [[ -f "los/firmware/j20s_novatek_ts_fw$n.bin.ihex" ]] || {
    echo "firmware layout of the kernel tree changed - manual inspection needed"; exit 1; }
done

echo "== [4/8] Checking whether this build already ships the fix firmware =="
cur01="$(objcopy -I ihex -O binary los/firmware/j20s_novatek_ts_fw01.bin.ihex /dev/stdout 2>/dev/null | sha256sum | cut -d' ' -f1)"
cur02="$(objcopy -I ihex -O binary los/firmware/j20s_novatek_ts_fw02.bin.ihex /dev/stdout 2>/dev/null | sha256sum | cut -d' ' -f1)"
if [[ "$cur01" == "$FW01_SHA" && "$cur02" == "$FW02_SHA" ]]; then
  echo ">>> This kernel revision already ships the V12.5.5.0 firmware for both"
  echo ">>> panels. This fix is obsolete for your build - stopping."
  exit 0
elif [[ "$cur01" == "$FW01_SHA" || "$cur02" == "$FW02_SHA" ]]; then
  echo "note: one of the two blobs already matches upstream; replacing both anyway."
else
  echo "shipped firmware differs (fw01 $(echo "$cur01" | cut -c1-12)..., fw02 $(echo "$cur02" | cut -c1-12)...) - continuing."
fi

echo "== [5/8] Installing and verifying the V12.5.5.0 fix firmware =="
cp "$HERE/firmware/j20s_novatek_ts_fw01.bin.ihex" los/firmware/j20s_novatek_ts_fw01.bin.ihex
cp "$HERE/firmware/j20s_novatek_ts_fw02.bin.ihex" los/firmware/j20s_novatek_ts_fw02.bin.ihex
rm -f fw01.bin fw02.bin
for n in 01 02; do
  var="FW${n}_SHA"; want="${!var}"
  objcopy -I ihex -O binary "los/firmware/j20s_novatek_ts_fw$n.bin.ihex" "fw$n.bin"
  have="$(sha256sum "fw$n.bin" | cut -d' ' -f1)"
  [[ "$have" == "$want" ]] || { echo "sha256 of fw$n does NOT match - corrupted source files?"; exit 1; }
done
echo "firmware hashes OK."

# Workaround: on hosts with CUDA installed, 'clang -v' also prints
# "Found CUDA installation: ..., version ..."; mkcompile_h greps for ' version '
# and would put two lines into one C string. Take only the first line.
# (The guard must match the CC_VERSION line specifically: the neighbouring
# LD_VERSION line already contains an unrelated 'head -n1'.)
grep -qF "grep ' version ' | head -n1" los/scripts/mkcompile_h || \
  sed -i "s/grep ' version ' |/grep ' version ' | head -n1 |/" los/scripts/mkcompile_h
grep -qF "grep ' version ' | head -n1" los/scripts/mkcompile_h || {
  echo "could not apply the mkcompile_h version-string workaround - inspect scripts/mkcompile_h"; exit 1; }

echo "== [6/8] Configuring and building the kernel (-j$JOBS, expect 10-25 min) =="
# Toolchain via absolute paths (NOT prepended to PATH): Proton's bundled host
# 'ld' is too old for modern glibc; host tools must use the system compiler.
MAKEVARS=(O=out ARCH=arm64
  CC="$TC/clang" CLANG_TRIPLE=aarch64-linux-gnu-
  CROSS_COMPILE="$TC/aarch64-linux-gnu-" CROSS_COMPILE_ARM32="$TC/arm-linux-gnueabi-"
  HOSTCC=gcc HOSTCXX=g++)
( cd los
  # This is the exact config stack LineageOS itself builds vayu with
  # (see BoardConfigCommon.mk in android_device_xiaomi_sm8150-common):
  make "${MAKEVARS[@]}" vendor/sm8150-perf_defconfig vendor/debugfs.config \
       vendor/xiaomi/sm8150-common.config vendor/xiaomi/vayu.config
  grep -q "^CONFIG_TOUCHSCREEN_NT36xxx_HOSTDL_SPI=y" out/.config || {
    echo "touchscreen driver missing from config - did the tree change?"; exit 1; }
  grep -q "^CONFIG_FIRMWARE_IN_KERNEL=y" out/.config || {
    echo "CONFIG_FIRMWARE_IN_KERNEL is off - firmware would not be embedded!"; exit 1; }
  # Build only 'Image': the 'dtbs' target trips over dtbo overlays of other
  # sm8150 devices and is not needed (we reuse the dtb from your boot.img).
  make "${MAKEVARS[@]}" -j"$JOBS" Image
)

echo "== [7/8] Proving both full firmware blobs are embedded in the kernel Image =="
python3 - <<'PYEOF'
img = open('los/out/arch/arm64/boot/Image', 'rb').read()
for name in ('fw01', 'fw02'):
    fw = open(f'{name}.bin', 'rb').read()
    n = img.count(fw)
    assert n == 1, f"ERROR: {name} found {n}x in the Image (expected exactly once)"
print(f"both complete V12.5.5.0 blobs found exactly once in the Image ({len(img)} bytes)")
PYEOF

echo "== [8/8] Repacking boot.img and verifying the result =="
NEWARGS="$(printf '%s' "$ARGS_IN" | sed 's|--kernel bootimg/kernel|--kernel los/out/arch/arm64/boot/Image|')"
eval python3 "$MKB/mkbootimg.py" $NEWARGS -o boot-touchfix-new.img

# Verification 1: both full firmware blobs present in the final image
python3 - <<'PYEOF'
img = open('boot-touchfix-new.img', 'rb').read()
for name in ('fw01', 'fw02'):
    fw = open(f'{name}.bin', 'rb').read()
    assert img.count(fw) == 1, f"{name} not embedded exactly once in output image?!"
PYEOF
# Verification 2: ramdisk and dtb byte-identical to the supplied boot.img
ARGS_OUT="$(python3 "$MKB/unpack_bootimg.py" --boot_img boot-touchfix-new.img --out bootimg-check --format mkbootimg)"
cmp bootimg/ramdisk bootimg-check/ramdisk
[[ -f bootimg/dtb ]] && cmp bootimg/dtb bootimg-check/dtb
# Verification 3: all boot header parameters (cmdline, offsets, os version,
# patch level, page size, header version, ...) identical to the input image
python3 - "$ARGS_IN" "$ARGS_OUT" <<'PYEOF'
import shlex, sys
def params(argstr):
    toks, d, i = shlex.split(argstr), {}, 0
    while i < len(toks):
        if toks[i].startswith('--'):
            key = toks[i][2:]
            val = toks[i+1] if i+1 < len(toks) and not toks[i+1].startswith('--') else ''
            if key not in ('kernel', 'ramdisk', 'dtb', 'second', 'recovery_dtbo'):
                d[key] = val
            i += 2 if val != '' else 1
        else:
            i += 1
    return d
a, b = params(sys.argv[1]), params(sys.argv[2])
assert a == b, f"boot header parameters differ!\n input: {a}\noutput: {b}"
print("boot header parameters (cmdline, offsets, versions) identical to input")
PYEOF
echo "ramdisk and dtb identical to the supplied boot.img."

OUT="$OUTDIR/boot-touchfix-$(date +%Y%m%d)-${KREF:0:12}.img"
mv boot-touchfix-new.img "$OUT"
echo
echo "================================================================"
echo "DONE: $OUT"
echo "kernel source revision: $KREF"
sha256sum "$OUT"
echo
echo "Flash it (phone in fastboot mode: power off, then Vol-down + Power):"
echo "  fastboot flash boot \"$OUT\""
echo "  fastboot reboot"
echo
echo "Rollback is always possible by flashing back the original boot.img"
echo "of your build. Keep it. After every LineageOS update, run this"
echo "script again with that build's own boot.img - do not reuse images"
echo "built for older builds."
echo "================================================================"
