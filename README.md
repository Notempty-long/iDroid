# iDroid

**Android on the iPhone 7.** A from-scratch port of a Treble GSI to Apple's A10
(`t8010`) using [HoolockLinux](https://github.com/HoolockLinux) for the kernel
and boot chain, with the iPhone's USB Ethernet gadget standing in for the
Android disk.

| | |
|---|---|
| Target | iPhone 7 (GSM / Intel), `iPhone9,3`, board `d101ap`, SoC `t8010` |
| Android | Android 16 QPR2 ARM64 GSI (`system`) + locally built `vendor` |
| Kernel | HoolockLinux `hoolock`, arm64, **16 KiB pages** |
| Boot chain | checkm8 → patched iBSS → m1n1 `idevice` → Linux |
| Storage | **netboot** — GPT disk image served over NBD via the USB Ethernet gadget |
| TEE | none (software Keymaster/Gatekeeper only) |
| Status | boot chain + host tooling scaffolded; Android userspace not yet booted |

## Why it looks like this

- **A10 is checkm8-vulnerable.** `remote_boot` loads Hoolock's m1n1 build as a
  fake restore kernel (the iBoot method). It is patched to hard-code this
  phone's identity because device info cannot be queried reliably after pwn.
- **16 KiB pages everywhere.** HoolockLinux's `config_16k` targets A10 with
  16 KiB pages, and Android 16 is the first release where Google requires
  16 KiB support on new 64-bit devices. Kernel, GSI, and vendor must agree.
- **There is no Android disk.** HoolockLinux documents internal-storage support
  only for A11. USB device mode does work, so the host serves a GPT disk image
  over NBD; Android sees ordinary block devices while the data stays on the host.
- **No TEE, no baseband.** Keymaster/Gatekeeper run in software (planned); there
  are no cellular calls and no hardware-backed DRM/attestation.

## Repository layout

```
docs/        device notes, boot chain, netboot, GSI, decisions, roadmap
config/      kernel fragment, kernel cmdline, GSI pin
patches/     tracked changes to vendored trees (applied after every sync)
vendor/      pinned upstream sources (git submodules, shallow)
scripts/     host tooling (guarded; nothing flashes the phone without asking)
out/         build artifacts (ignored)
cache/       downloads and extracted images (ignored)
```

## Quick start (host)

Requirements: Linux x86_64 or arm64, root for booting/netboot, ~10 GB free,
`clang`, `ld.lld`, `git`, `make`, `ipsw` ≥ 3.1.719, `irecovery`, `libusb` dev
headers, `qemu-nbd`, `dnsmasq`, `sgdisk`, `unzip`, `xxd`, `lsusb`.

```sh
scripts/check-host.sh        # verify host dependencies
scripts/vendor-sync.sh       # fetch pinned sources + apply patches
scripts/fetch-m1n1.sh        # download prebuilt m1n1-idevice + monitor-stub
scripts/build-kernel.sh      # Image.gz + t8010-d101.dtb (16K pages)
scripts/fetch-gsi.sh         # download + checksum + extract Android 16 GSI
scripts/netboot/make-disk.sh # create the NBD disk image (GPT)
scripts/build-m1n1-blob.sh   # concatenate the m1n1 boot bundle
scripts/boot.sh              # phone must be in DFU; runs remote_boot
```

`make <target>` wraps the same commands; `make help` lists them.

## Vendored sources

| Path | Upstream | Branch |
|---|---|---|
| `vendor/linux` | HoolockLinux/linux | `hoolock` |
| `vendor/m1n1` | HoolockLinux/m1n1 | `idevice` |
| `vendor/remote_boot` | HoolockLinux/remote_boot | `master` |
| `vendor/projectsandcastle` | corellium/projectsandcastle | `master` |
| `vendor/docs` | HoolockLinux/docs | `master` |

Pins are the gitlinks in this repository plus `vendor/versions.lock`. Never edit
a vendored tree in place: changes go in `patches/<submodule>/` and are applied by
`scripts/apply-patches.sh`, so they survive a resync and rebase.

## Non-goals

- Installing to internal storage (unsupported on A10 under HoolockLinux)
- Hardware GPU acceleration (display works; GPU is TBA upstream)
- Cellular modem, calls, SMS (baseband is not supported)
- TEE-backed keys, Widevine L1, hardware attestation

## Licensing / redistribution

The Google GSI is for development and app validation; do not commit or
redistribute it (see `docs/gsi.md`). Kernel and bootloader sources keep their
upstream licenses (GPL-2.0 / BSD-3-Clause).
