# GSI and vendor interface

## Choice: Android 16 QPR2 ARM64 GSI (no GMS)

Pinned in `config/gsi.env`:

```
aosp_arm64-exp-BP4A.251205.006-14401865-2171cf0e.zip
sha256 2171cf0ea849f8eaa399f4bad2165fab80b0fd9e98d37723a705dca6c41e49ea
```

Reasons:

- **16 KiB pages**: Android 15+ supports 16 KiB and Android 16 is the first
  release where Google requires 16 KiB support on new 64-bit devices. Matching
  the kernel's 16 KiB page size is mandatory, not optional.
- **No VNDK**: the VNDK is deprecated as of Android 15, and the vendor snapshot
  mechanism was removed with it. For an Android 16 vendor built here, vendor
  libraries live in `vendor` and link against the LLNDK. There is no VNDK
  version to match, which is why "whichever is best" is answered by "newest
  release without VNDK".
- **No GMS**: smaller, fewer proprietary dependencies, easier to audit. Use the
  no-GMS `aosp_arm64` image, not `gsi_gms_arm64`.
- **QPR2 stable**: more field testing than the initial release; upgrade to
  Android 17 later once bring-up is stable.

Do **not** commit the image or its extracted contents: Google's GSI license is
for development/app validation, not redistribution.

## Fetch and verify

```sh
scripts/fetch-gsi.sh                     # uses config/gsi.env
scripts/fetch-gsi.sh URL SHA256          # or an explicit pin
scripts/check-gsi-16k.sh                 # verify 16 KiB ELF alignment
```

`fetch-gsi.sh` downloads to `cache/downloads/`, verifies SHA-256, extracts to
`cache/gsi/<name>/`, and points `cache/gsi/current` at it. `system.img` is the
only artifact used for now; `vbmeta.img` from the GSI is ignored (we build our
own with verification disabled).

## 16 KiB verification

A 16 KiB kernel cannot run system libraries whose ELF `LOAD` segments are only
4 KiB aligned. `check-gsi-16k.sh` uses `debugfs` to extract `libc.so` (and
`init` if present) and reports the maximum `p_align`:

- `0x4000` (16384) or greater → compatible.
- `0x1000` (4096) → not compatible; do not expect a boot. Build the system
  image from AOSP with 16 KiB pages, or use a GSI explicitly built for 16 KiB.

Note that ext4 block size does **not** have to equal the page size; a 4 KiB
ext4 filesystem mounts fine on a 16 KiB kernel. ELF alignment is the blocker.

## Vendor interface

| Component | Source | Notes |
|---|---|---|
| `system` | GSI | read-only, 16 KiB |
| `vendor` | built here | HALs, firmware, init scripts, policy, `hx-touchd` |
| `product` | from GSI / vendor | optional split |
| `vbmeta` | built here | `--disable-verity --disable-verification` |
| `userdata` | host-created ext4 | wiped between experiments |

HALs needed for first light (AIDL, Android 16):

- `android.hardware.graphics.allocator` + `composer` (software/DRM)
- `android.hardware.input` (evdev from `hx-touchd`)
- `android.hardware.audio` (stub or simple card)
- `android.hardware.lights`
- `android.hardware.health`
- `android.hardware.power` / `android.hardware.thermal` (stubs acceptable)

Vendor init must start `hx-touchd` after `/dev/i2c-*` and `/dev/uinput` exist,
and must set the display mode expected by the panel (750×1334).

## AVB / verification

iBoot does not verify `vbmeta`, but Android's init does. Build a vbmeta image
with both flags disabled and pass:

```
androidboot.verifiedbootstate=orange
androidboot.selinux=permissive    # bring-up only
```

Once Android boots, re-enable SELinux enforcing with a policy covering only our
vendor services; full CTS is out of scope.
