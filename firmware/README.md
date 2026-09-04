# Firmware provenance

Both files are Novatek NT36672C touch controller firmware for the
POCO X3 Pro (vayu, internal codename j20s), version **V12.5.5.0.RJUIDXM
prod** as labeled by the upstream kernel commit that introduced them.
They are vendor firmware blobs (Xiaomi/Novatek), not covered by this
repository's GPL-2.0 license; original vendor licensing terms, if any,
continue to apply.

## Source

- Upstream repository: <https://github.com/elizabethangelalorenza/kernel_xiaomi_vayu>
- Upstream commit: `4e6d9128` - *"firmware: Switch NT36xxx firmware blobs to
  V12.5.5.0.RJUIDXM prod"* (2021-12-15)
- Upstream paths: `firmware/j20s_novatek_ts_fw01.bin.ihex`,
  `firmware/j20s_novatek_ts_fw02.bin.ihex`
- Cross-check: byte-identical (decoded) to the default
  `j20s_novatek_ts_fw01/02.bin.ihex` in
  <https://github.com/LuffyTaro008/android_kernel_xiaomi_vayu>, branch `13`.

## Related builds with the same version label

The No Gravity kernel tree
(<https://github.com/Pierre2324/NGK_android_kernel_xiaomi_sm8150>, branches
`s-caf`/`t-caf`) carries files named `j20s_novatek_ts_fw01/02_V12.5.5.0.bin.ihex`
that are **not** byte-identical to the files here: its fw01 (decoded
`19aada957174...`) is the same build apart from 33 bytes of version/tuning
fields; its fw02 (decoded `688e6ef88151...`) is a substantially different CSOT
build - plausibly regional or panel-batch variants of the same MIUI release.
In LuffyTaro's hash-suffixed collection those NGK files appear as
`fw01.2fa7` and `fw02.fd13`.

## Modification

The upstream `.ihex` files carry CRLF line endings; the copies here are
normalized to LF (this keeps `git am`/`git apply` results consistent and
satisfies kernel `checkpatch` whitespace rules). Intel-HEX semantics and the
decoded firmware bytes are unchanged.

## Hashes

| File | sha256 (file, LF) | sha256 (decoded binary) |
|---|---|---|
| `j20s_novatek_ts_fw01.bin.ihex` | `97e4b7c993997526af5162e7f52b07b56b978f353e658559ae34f13d8c7666cb` | `610f3521e3fb384f11f43d49a71e9eb9e8990f0b004d0a7532ec749e2b866334` |
| `j20s_novatek_ts_fw02.bin.ihex` | `61a15a3ea280500bb3c68703bde9b88facb6fc47a84a6d0d857861a786c0f8f0` | `7392a835cca1296f552c613a9678722a5312403950018ff1af27f4adc704cb7e` |

Decode with: `objcopy -I ihex -O binary <file>.ihex /dev/stdout | sha256sum`
(each decodes to 139264 bytes).
