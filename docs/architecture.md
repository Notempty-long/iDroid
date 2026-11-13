# Architecture

## Boot flow

```
host (Linux)                                     iPhone 7 (A10 / t8010)
┌──────────────────────────────┐   Lightning   ┌──────────────────────────────────┐
│ remote_boot                  │──────────────▶│ DFU (checkm8)                    │
│  patched iBSS (IMG4)         │               │  → pwned iBoot                   │
│  RestoreDeviceTree (IMG4)    │               │  → m1n1-idevice (fake rkrn)      │
│  RestoreKernelCache =        │               │  → monitor-stub                  │
│    m1n1 + bootargs + dtb +   │               │  → Hoolock Linux (16K pages)     │
│    Image.gz + initramfs      │               │  → initramfs                     │
└──────────────────────────────┘               │       usb0: 192.168.137.1/24     │
                                               │       DHCP from host             │
┌──────────────────────────────┐   usbnet      │       nbd-client                 │
│ dnsmasq  (DHCP)              │◀─────────────▶│  → /dev/nbd0 (GPT)               │
│ qemu-nbd (system/vendor/     │               │  → mount system/vendor/userdata  │
│           userdata/vbmeta)   │               │  → exec Android init             │
└──────────────────────────────┘               └──────────────────────────────────┘
```

## Pieces

| Piece | Role | Source |
|---|---|---|
| `gaster` | checkm8 exploit / DFU pwn | `remote_boot/vendor` |
| patched iBSS | unsigned restore stage | `remote_boot prep` |
| `m1n1-idevice` | bare-metal loader, loads the Mach-O payload | Hoolock m1n1 nightly |
| `monitor-stub` | mock XNU watchtower for the two-stage path | Hoolock m1n1 nightly |
| `Image.gz`, `t8010-d101.dtb` | Linux kernel + device tree | `vendor/linux` |
| initramfs | brings up usb0, DHCP, NBD, mounts Android | `out/` (built here) |
| GSI `system.img` | Android framework/userspace | Google |
| `vendor.img` | HALs, firmware, SELinux policy, `hx-touchd` | built here |
| `userdata.img` | mutable data | created on host |
| `vbmeta.img` | AVB metadata (verification disabled) | created on host |

The iBoot method is used because it does not depend on anything on internal
storage, which this port cannot use. `POST`-pwn device information is unreliable
in this setup, so `patches/remote_boot/0001-…` hard-codes `CPID=0x8010`,
`MODEL=d101ap`, `PRODUCT=iPhone9,3`. `0x8010` is not in `remote_boot`'s
`two_stage` list, so only iBSS is used (no iBEC stage).

## Android side

- **Treble split**: `system` comes from the GSI; `vendor` is ours. The kernel is
  ours (not GKI), so the GSI's GKI artifacts are ignored.
- **Page size**: 16 KiB kernel. Android 16 is the first release where Google
  requires 16 KiB support on new 64-bit devices, and its GSI is built for it.
- **VNDK**: deprecated in Android 15; vendor snapshot was removed with it.
  Vendor libraries live in `vendor` and link against LLNDK. There is no VNDK
  version to match for an Android 16 GSI (see `docs/decisions.md`).
- **Block devices**: NBD gives a real GPT disk. Android's first-stage init gets a
  custom fstab in the ramdisk that points at `/dev/block/nbd0pN`, with ueventd
  rules creating `by-name` symlinks.
- **AVB**: iBoot does not verify Android's vbmeta, but Android's init does.
  Ship a vbmeta with verification/verity disabled for bring-up.
- **SELinux**: permissive during bring-up only (`androidboot.selinux=permissive`);
  enforcing requires a policy for our HALs and init services.
- **Keymaster/Gatekeeper**: software implementations (no TEE). Some CTS paths
  will never pass; that is accepted.
- **Display**: kernel exposes the panel; bring-up uses software composition
  until a DRM/HWC HAL exists. No GPU acceleration.
- **Input**: `hx-touchd` reads the touch controller over I2C and injects events
  through `/dev/uinput`; Android's InputReader sees a normal evdev device.
- **Network**: `usb0` (CDC-ECM) via Android EthernetService; no Wi-Fi/BT bring-up
  in the first milestone.

## Build outputs

| Output | Producer | Contents |
|---|---|---|
| `out/kernel/` | `scripts/build-kernel.sh` | `Image.gz`, `t8010-d101.dtb`, merged `.config`, commit pin |
| `out/boot/m1n1-linux.macho` | `scripts/build-m1n1-blob.sh` | m1n1 + bootargs + dtb + kernel (+ initramfs) |
| `out/boot/monitor-stub.macho` | `scripts/fetch-m1n1.sh` | second-stage stub |
| `out/disk.img` | `scripts/netboot/make-disk.sh` | GPT: vbmeta, system, vendor, userdata |
| `out/vendor/` | *(milestone 3)* | vendor image + firmware + HALs |
