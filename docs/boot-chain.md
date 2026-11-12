# Boot chain (iBoot method)

Reference: `vendor/docs/tutorials/SETUP.md` and `SETUP_iBoot.md`.

## 1. Host prerequisites

- `irecovery` (libimobiledevice)
- `ipsw` ≥ 3.1.719 (older versions generate broken LZSS IMG4 files)
- `clang`, `xxd`, `git`, `lsusb`, GNU make
- `libusb-1.0` development headers (to build `gaster`)

## 2. m1n1

Use the prebuilt idevice build:

```sh
scripts/fetch-m1n1.sh
```

It downloads
`https://nightly.link/hoolocklinux/m1n1/workflows/build/idevice/m1n1.zip`
and expects `m1n1-idevice.macho` and `monitor-stub.macho`. The nightly is a
moving target: the script records the archive SHA-256 in
`cache/m1n1/m1n1.sha256`; pin it by setting `M1N1_SHA256` once you have a known
good build.

A from-source build uses the same stable API:

```sh
git -C vendor/m1n1 submodule update --init --recursive
make -C vendor/m1n1 -j"$(nproc)" CHAINLOADING=1
```

## 3. Prepare the boot files (once per model)

```sh
sudo vendor/remote_boot/remoteboot.sh prep
```

This downloads the signed iBSS/DeviceTree for `iPhone9,3` from Apple, patches
iBSS with `hBootPatcher`, and writes IMG4 files into `vendor/remote_boot/cache/`.
`prep` needs internet access and the phone **in DFU** (it pwns the device first).

The local patch is required: `remote_boot` normally derives `CPID`, `MODEL`, and
`PRODUCT` from `irecovery -q`, which is unreliable after pwn on this setup.
`patches/remote_boot/0001-hardcode-iphone9-3-device-info.patch` hard-codes
`0x8010` / `d101ap` / `iPhone9,3`.

## 4. Build the m1n1 payload

```sh
scripts/build-kernel.sh
scripts/build-android-initramfs.sh
INITRAMFS=out/initramfs/initramfs.gz scripts/build-m1n1-blob.sh
```

Per Hoolock's documentation, the payload is a concatenation:

```
m1n1-idevice.macho
chosen.bootargs=<kernel command line>\n
t8010-d101.dtb
Image.gz
initramfs.gz
```

m1n1 parses the appended files and boots the kernel with that DT and command
line. `scripts/build-m1n1-blob.sh` performs exactly this concatenation and
copies `monitor-stub.macho` next to it.

Kernel command line defaults live in `config/cmdline`. Keep it short; Android
boot parameters are added by the Android ramdisk/bootconfig.

## 5. Boot

Phone in DFU, then:

```sh
sudo scripts/boot.sh
```

The script confirms before executing and calls:

```sh
vendor/remote_boot/remoteboot.sh boot \
  out/boot/m1n1-linux.macho \
  out/boot/monitor-stub.macho
```

Notes:

- `remote_boot` only needs `prep` once per model; `boot` is offline.
- On some hosts the cable must be re-plugged after sending iBSS. The tool prints
  a hint; this is expected, not a failure.
- `0x8010` is not in the two-stage list, so there is **no** iBEC stage. If you
  see iBEC logic attempted, the patch did not apply.
- If the phone boots back to iOS or recovery, the pwn failed: re-enter DFU and
  retry `prep` (checkm8 on A10 can need several attempts).

## 6. Verifying Linux before Android

Success for this milestone:

1. Display shows Hoolock's boot output / framebuffer console.
2. Host sees a new USB network interface (typically `usb0`).
3. Host `172.16.42.2` can reach the device at `172.16.42.1` (telnet port 23).
4. `lsusb` shows the gadget re-enumerated (Apple VID/PID plus a network function).
5. The console prints `iDroid first stage starting`, then the NBD connection
   and mount messages from `/android.sh`.

With the Android ramdisk the phone proceeds straight into the Android handoff.
Add `idroid_debug=1` to `config/cmdline` to stay in the Linux shell instead; see
`docs/netboot.md`.

Only after that should the Android rootfs be involved.
