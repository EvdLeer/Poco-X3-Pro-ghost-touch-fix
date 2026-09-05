# Ghost touch fix for POCO X3 Pro (vayu) on LineageOS

Random phantom taps, ghost scrolling, text selecting itself, buttons pressing
on their own - the infamous POCO X3 Pro **ghost touch** problem, on LineageOS
and other custom ROMs.

This repository contains a minimal, verifiable fix:
the touch controller firmware from **MIUI V12.5.5.0.RJUIDXM**, a firmware
version that has been used by existing vayu kernels to address the
ghost-touch issue, plus the tooling to get it into an otherwise **stock
LineageOS kernel build, changing only the two embedded touchscreen firmware
blobs**.

## Just want the fix?
You do not need to build anything: ready-made images are published for each recent nightly - see
[Option A - install a prebuilt image](#option-a---install-a-prebuilt-image-easiest).

> ## ⚠️ Status: EXPERIMENTAL - under test
>
> | Device | Panel | ROM / build | Result | Since |
> |---|---|---|---|---|
> | test device 1 | Tianma → fw01 (`read-panel.sh`) | LineageOS 22.2 (nightly 20260719) | zero ghost touches since flashing - previously multiple episodes daily | 2026-09 |
> | test device 2 | Tianma → fw01 (`read-panel.sh`) | LineageOS 22.2 (nightly 20260816) | zero ghost touches since flashing - previously multiple episodes daily | 2026-09 |
>
> Two devices and a short test window are a strong first indication, not
> proof. Both test devices use the **Tianma** panel, so the CSOT blob (fw02)
> is still empirically unconfirmed - CSOT test reports are especially
> welcome. If you try this, please open an issue with your panel type (see
> [Which panel do I have?](#which-panel-do-i-have)), ROM/build, and whether
> the ghost touches stopped. That evidence is what could get this change
> merged into LineageOS proper.

## Why this can work

- The X3 Pro's **Novatek NT36672C** is a *no-flash* ("host download") touch
  IC: it has no firmware storage of its own. The kernel uploads the touch
  firmware to the controller **on every boot** (as a delayed firmware update
  shortly after the driver starts; see `BOOT_UPDATE_FIRMWARE` /
  `Boot_Update_Firmware()` in the driver).
- That firmware is **embedded in the kernel image** as
  `firmware/j20s_novatek_ts_fw01.bin.ihex` and `..._fw02.bin.ihex` - see the
  `fw-shipped-$(CONFIG_TOUCHSCREEN_NT36xxx_HOSTDL_SPI)` rules in the kernel's
  [`firmware/Makefile`](https://github.com/LineageOS/android_kernel_xiaomi_sm8150/blob/lineage-22.2/firmware/Makefile).
  There is no runtime firmware file under `/vendor/firmware` that a
  conventional Magisk file overlay could replace; the kernel image itself has
  to contain the replacement firmware.
- The driver selects fw01 or fw02 by matching panel **lockdown info** against
  a config array in the device tree (for TP vendor `0x46` an additional
  glass-vendor byte is checked), with a display-name fallback. On vayu the DT
  (`arch/arm64/boot/dts/qcom/xiaomi/overlay/vayu/vayu-sm8150.dtsi`) maps TP
  vendor `0x46` (config named `nvt+tianma`) → fw01 and `0x53` (`nvt+csot`;
  CSOT is also known as Huaxing in vayu documentation) → fw02. Both blobs
  are replaced by this fix.
- LineageOS ships a different (newer) firmware version. Swapping the two
  embedded blobs to the V12.5.5.0 version is the entire intended change: no
  functional kernel, driver, DTS or config source is modified. (On affected
  build hosts the build script applies one host-build-only workaround to
  `scripts/mkcompile_h`, which only influences how the version banner is
  generated during the build.)

**Why firmware-only?** This approach was first demonstrated by XDA user
**Mkdir1511** in
[post #1366 (page 69) of the LineageOS 22.2 vayu thread](https://xdaforums.com/t/rom-v-official-lineageos-22-2-for-poco-x3-pro-vayu-bhima.4301199/page-69)
(March 2026), who rebuilt LineageOS with the firmware *and* touchscreen
driver from the [No Gravity kernel](https://github.com/Pierre2324/NGK_android_kernel_xiaomi_sm8150),
and was confirmed by user jacksp in post #1368: *"I can confirm it works
perfectly!"*. Mkdir1511 already suspected that not every step was necessary
("maybe it is already enough to replace firmware or drivers").
A C-token-level comparison (ignoring all formatting and
comments) of the firmware-update path between the two trees involved -
`LineageOS/android_kernel_xiaomi_sm8150` @ `59220a048d04` vs
`elizabethangelalorenza/kernel_xiaomi_vayu` @ `29ac0068` - shows
`nt36xxx_fw_update.c` identical apart from an `#if BOOT_UPDATE_FIRMWARE`
wrapper and an extra debugfs test-firmware branch in LineageOS, and
`nt36xxx_mem_map.h` differing only in trailing commas. (The main driver file
does carry LineageOS-specific extras, but none of them touch how the
firmware is chosen or uploaded.) This strongly indicates the firmware blobs
are the operative change, which is why this fix swaps only those - and the
test results above are consistent with that.

**A precision note on "V12.5.5.0":** two different blob sets carry that
label in public trees. This repo ships the set labeled *"V12.5.5.0.RJUIDXM
prod"* by the community tree that introduced it (decoded `610f3521...` /
`7392a835...`), which is also the default j20s firmware in several community
kernels. The No Gravity kernel's own tree carries files named
`..._V12.5.5.0.bin.ihex` whose **fw01 is the same build apart from 33 bytes**
of version/tuning fields (decoded `19aada95...`), but whose **fw02 (CSOT) is
a substantially different build** (decoded `688e6ef8...`) - plausibly
regional or panel-batch variants of the same MIUI release. Mkdir1511's
validated rebuild used the NGK set; the devices in the status table above
run this repo's set. For Tianma panels the two are effectively the same
firmware; for CSOT panels both candidates exist (see the alternatives
below), and panel-specific test reports are especially welcome.

## Repository layout

```
firmware/            the two V12.5.5.0.RJUIDXM prod .ihex blobs (LF-normalized)
firmware/README.md   provenance: upstream source, commits, hashes
patches/0001-*.patch git am-able patch for kernel maintainers
build-touchfix.sh    end-to-end build script for end users
read-panel.sh        reports your panel variant (Tianma/fw01 vs CSOT/fw02) via adb
.github/workflows/   CI that builds a release for each LineageOS nightly
LICENSE              GPL-2.0 (both scripts and the patch; see License below)
```

## Option A - install a prebuilt image (easiest)

Ready-made images for recent LineageOS nightlies are on the
[Releases page](https://github.com/EvdLeer/Poco-X3-Pro-ghost-touch-fix/releases).
You need a computer, a USB cable, a POCO X3 Pro that already runs official
LineageOS 22.2 (so your bootloader is already unlocked), and Google's
[platform-tools](https://developer.android.com/tools/releases/platform-tools)
(the `fastboot` command) unpacked somewhere on that computer.

1. On the phone, check which build you are running: Settings > About phone >
   LineageOS version, for example `22.2-20260830-NIGHTLY-vayu`. The date is
   the part that matters.
2. Open the release whose title ends in that date and download
   `boot-touchfix-vayu-lineage-22.2-<date>.img`. Also download
   `boot-original-vayu-lineage-22.2-<date>.img` - that is your way back.
   **Only flash images whose date exactly matches your installed build.**
3. Switch the phone off. Hold Volume-down + Power until the FASTBOOT screen
   appears, then connect the phone to the computer.
4. Open a terminal (Windows: Command Prompt) in the folder with the
   downloaded images and run:

   ```
   fastboot flash boot boot-touchfix-vayu-lineage-22.2-<date>.img
   fastboot reboot
   ```

   (Windows: if `fastboot` is not recognized, run it from the platform-tools
   folder, e.g. `C:\platform-tools\fastboot.exe`.)
5. The phone boots normally. Apps, settings and data are untouched; only the
   boot partition changed. The ghost touches should be gone.

Going back is always possible: flash the `boot-original-...` image the same
way. If the phone will not boot, fastboot mode (Volume-down + Power) always
remains reachable.

**After every LineageOS update (OTA)** the update restores the stock kernel
and the ghost touches will return. Download and flash the image matching the
new build; a release for each new nightly normally appears within a day.

The prebuilt images are produced automatically by GitHub Actions
([workflow](.github/workflows/build-touchfix.yml)) from an unmodified
official LineageOS `boot.img` plus this repository's build script. Every
release includes the full build log, checksums (`SHA256SUMS`) and source
details, and is marked as a prerelease: CI does not test on a physical
phone. The images are exactly what Option B below produces.

## Option B - build it yourself (advanced)

Requirements: Linux x86_64, ~8 GB free disk, and
`gcc g++ make bc openssl python3 binutils curl tar libssl-dev`.

1. Download the `boot.img` that matches your **installed** nightly from
   [download.lineageos.org/devices/vayu/builds](https://download.lineageos.org/devices/vayu/builds)
   (separate file next to the ROM zip).
2. Run:

   ```
   ./build-touchfix.sh ~/Downloads/boot.img
   ```

3. Flash the resulting `boot-touchfix-YYYYMMDD-<rev>.img` (bootloader must
   be unlocked; phone in fastboot mode):

   ```
   fastboot flash boot boot-touchfix-YYYYMMDD-<rev>.img
   fastboot reboot
   ```

The script is designed to be reproducible and paranoid:

- **Builds the exact source revision of your build**: official LineageOS
  kernels embed their git revision in the kernel version string
  (e.g. `-g59220a048d04`); the script extracts it from your boot.img and
  downloads precisely that revision - no silent branch drift. An explicit
  ref can be passed as a second argument; toolchain (Proton Clang 13) and
  AOSP mkbootimg are pinned to fixed commits.
- Verifies the firmware hashes before building, asserts the touchscreen and
  firmware-embedding kernel config options, and proves that **both complete
  decoded blobs occur exactly once** in the built kernel Image and in the
  final boot image.
- Repacks your own boot.img and then verifies that the ramdisk and DTB are
  byte-identical and that **all boot header parameters** (cmdline, offsets,
  OS version/patch level, page size, header version) match the input image.
- Detects when the kernel revision you are building **already ships this
  firmware for both panels** - if LineageOS ever merges the fix, the script
  says so and stops, and this repo is obsolete.

Tested baseline: LineageOS 22.2 nightly 20260816 (kernel `59220a048d04`).
Your data is untouched (only the boot partition changes) and rollback is
always possible: `fastboot flash boot <original boot.img>`.

## Option C - for ROM & kernel maintainers

Apply [`patches/0001-firmware-switch-NT36xxx-blobs-to-V12.5.5.0.patch`](patches/0001-firmware-switch-NT36xxx-blobs-to-V12.5.5.0.patch)
onto your kernel tree:

```
git am 0001-firmware-switch-NT36xxx-blobs-to-V12.5.5.0.patch
```

Verified to apply cleanly (and produce files byte-identical to
`firmware/` in this repo) against `LineageOS/android_kernel_xiaomi_sm8150`
at `59220a048d04` and at the `lineage-22.2` HEAD as of 2026-09-02. The patch
touches only the two `.ihex` files - no driver, DTS or config changes. Any
vayu tree with the standard `firmware/j20s_novatek_ts_*.bin.ihex` layout
qualifies (crDroid, PixelOS, Evolution X, etc. share this kernel base).
`git apply` produces byte-identical results if you prefer to commit
yourself.

## Verifying

| What | sha256 |
|---|---|
| fw01 **decoded** (V12.5.5.0, `nvt+tianma`) | `610f3521e3fb384f11f43d49a71e9eb9e8990f0b004d0a7532ec749e2b866334` |
| fw02 **decoded** (V12.5.5.0, `nvt+csot`) | `7392a835cca1296f552c613a9678722a5312403950018ff1af27f4adc704cb7e` |
| `firmware/...fw01.bin.ihex` (file) | `97e4b7c993997526af5162e7f52b07b56b978f353e658559ae34f13d8c7666cb` |
| `firmware/...fw02.bin.ihex` (file) | `61a15a3ea280500bb3c68703bde9b88facb6fc47a84a6d0d857861a786c0f8f0` |

Decode an ihex for comparison with:
`objcopy -I ihex -O binary <file>.ihex /dev/stdout | sha256sum`

For reference, LineageOS 22.2 currently ships decoded fw01 `bdbd2b81...` /
fw02 `6b269eb7...`. A kernel built by the script identifies itself via
`uname -r` as `4.14.356-openela-rc1-perf` *without* a `-g<hash>` suffix.

The build script verifies the full decoded blobs inside the images. For a
quick manual spot-check of a prebuilt image, these 32-byte sequences from
the fix firmware should be present:

```
fw01: 3f3a23942049003f50c0212e17c9a32e07e8fd8e21e020e80296083814820244
fw02: 3f3a23942049003e8fc0212e17c9a32e07e8fd8e21e020e80296083814820244
```

## Which panel do I have?

With the phone connected over USB (USB debugging on), run
[`./read-panel.sh`](read-panel.sh) - it reads the DSI display name from the
kernel cmdline (maker `36` → Tianma, `42` → CSOT), falls back to the
touchscreen lockdown sysfs (TP vendor `0x46`/`0x53`), and, on rooted
devices, to the driver's dmesg output. Both blobs are replaced by this fix,
so you don't need to know in advance - but please mention the result when
reporting.

## Good to know

- **Every LineageOS OTA replaces the boot partition** and thus removes the
  fix. After every LineageOS update, flash the release matching the new
  build (or rebuild with the script and that build's boot.img) - never
  flash an image built for a different build date.
- Enable **Developer options → Pointer location** to make ghost touches
  visible while testing. Typical triggers: charging (especially cheap
  chargers), a warm device, low battery.
- If this repo's blobs do not help on your unit, alternatives exist -
  same recipe, different blob:
  - the [No Gravity kernel tree](https://github.com/Pierre2324/NGK_android_kernel_xiaomi_sm8150)
    (branches `s-caf`/`t-caf`) carries version-named variants:
    `..._V12.5.5.0` (the set Mkdir1511's rebuild used; its fw02 is a
    different CSOT build than ours - the first thing to try on a CSOT
    panel), `..._V12.0.6.0` and `..._V13.0.3.0`;
  - [LuffyTaro008/android_kernel_xiaomi_vayu](https://github.com/LuffyTaro008/android_kernel_xiaomi_vayu)
    (branch `13`) carries the same and more as hash-suffixed variants
    (`fw01.{2f0c,2fa7,3a42,8ac8}`, `fw02.{71e7,9874,fd13}`; `.2fa7`/`.fd13`
    = NGK's V12.5.5.0 set, `8ac8`/`71e7` = what LineageOS currently ships).

  If the same problem also occurs on stock MIUI, a hardware-related issue
  becomes more likely and firmware replacement may not help.

## Build script troubleshooting

Known pitfalls the script already works around:

1. Proton Clang's bundled host `ld` is too old for modern glibc
   (`unknown type [0x13] section '.relr.dyn'`) → toolchain is invoked via
   absolute paths with `HOSTCC=gcc`.
2. On hosts with CUDA, `clang -v` prints an extra "..., version ..." line that
   corrupts `mkcompile_h`'s generated header → patched with `head -n1`.
3. `make dtbs` fails on dtbo overlays of other sm8150 devices → only
   `Image` is built; your boot.img's dtb is reused (the touch DT node lives
   in the dtbo partition anyway, which is never touched).
4. kbuild cannot build under paths containing spaces → build happens in
   `~/.cache/vayu-touchfix`.

## Upstreaming

The goal is to make this repo unnecessary by getting the firmware switch
merged into `LineageOS/android_kernel_xiaomi_sm8150`. Historical LineageOS
reports of this problem include
[#4309](https://gitlab.com/LineageOS/issues/android/-/issues/4309) and
[#5679](https://gitlab.com/LineageOS/issues/android/-/issues/5679) on the
former GitLab issue tracker. Test reports in this repo's issue tracker
directly support the upstreaming effort.

## Credits & provenance

- **Mkdir1511**, who first demonstrated the rebuild-with-V12.5.5.0-firmware
  approach in
  [post #1366 of the LineageOS 22.2 vayu thread](https://xdaforums.com/t/rom-v-official-lineageos-22-2-for-poco-x3-pro-vayu-bhima.4301199/page-69),
  and **jacksp**, who independently confirmed it (post #1368).
- **Pierre2324**'s [No Gravity kernel](https://github.com/Pierre2324/NGK_android_kernel_xiaomi_sm8150),
  whose version-named firmware collection underpins that rebuild and
  corroborates the fw01 build shipped here.
- The blobs in this repo were taken from
  [elizabethangelalorenza/kernel_xiaomi_vayu](https://github.com/elizabethangelalorenza/kernel_xiaomi_vayu)
  (commit `4e6d9128`, *"firmware: Switch NT36xxx firmware blobs to
  V12.5.5.0.RJUIDXM prod"*) and are byte-identical to the defaults in
  [LuffyTaro008/android_kernel_xiaomi_vayu](https://github.com/LuffyTaro008/android_kernel_xiaomi_vayu)
  (branch `13`). Full per-file provenance:
  [firmware/README.md](firmware/README.md).
- [kdrag0n/proton-clang](https://github.com/kdrag0n/proton-clang) toolchain;
  AOSP `mkbootimg` tools.

## License

`build-touchfix.sh`, `read-panel.sh` and the patch are licensed under
**GPL-2.0**; see [LICENSE](LICENSE).

The files under `firmware/` are vendor firmware blobs and are **not** covered
by that GPL-2.0 license. They are redistributed unchanged (apart from
line-ending normalization, documented in
[firmware/README.md](firmware/README.md)) from publicly available kernel
source repositories for this device. Their original vendor licensing terms,
if any, continue to apply.

No warranty is provided. Flashing a modified boot image is at your own risk.
Keep the boot image matching your installed LineageOS build for rollback.
