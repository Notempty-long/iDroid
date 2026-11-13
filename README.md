# iDroid

**Linux on the iPhone 7.** Boots an Alpine Linux rootfs on Apple's A10
(`t8010`) using the [HoolockLinux](https://github.com/HoolockLinux) kernel and
boot chain, with the rootfs served over NBD through the phone's USB Ethernet
gadget.

| | |
|---|---|
| Target | iPhone 7 (GSM / Intel), `iPhone9,3`, board `d101ap`, SoC `t8010` |
| Kernel | HoolockLinux `hoolock`, arm64, **16 KiB pages** |
| Boot chain | checkm8 → patched iBSS → m1n1 `idevice` → Linux |
| Rootfs | Alpine Linux 3.24 aarch64 (musl/BusyBox), ext4 on `/dev/nbd0p1` |
| Storage | **netboot** — GPT disk image served over NBD via the USB Ethernet gadget |
| Link | phone `192.168.137.1`, host `192.168.137.2` (`config/netboot.conf`) |
| Status | boot chain + NBD rootfs working; touch/WiFi/BT not yet supported by the kernel |

## Why it looks like this

- **A10 is checkm8-vulnerable.** `remote_boot` loads Hoolock's m1n1 build as a
  fake restore kernel (the iBoot method). It is patched to hard-code this
  phone's identity because device info cannot be queried reliably after pwn.
- **There is no usable internal disk.** Hoolock's T8010 device tree describes no
  NVMe/ANS2 block device, and no PCIe host either. USB device mode does work, so
  the host serves a GPT disk image over NBD; the phone sees an ordinary root
  block device while the data stays on the host.
- **16 KiB pages.** Hoolock's `config_16k` targets A10 with 16 KiB pages. Keep
  the kernel and userspace on the same page size; Alpine's aarch64 userland is
  built with 64 KiB ELF alignment and runs fine.
- **No TEE, no baseband.** No cellular calls, no hardware-backed DRM or
  attestation.

## Quick start

```sh
make check                 # host dependencies
make vendor                # sync pinned submodules + patches
make kernel                # out/kernel/Image.gz + t8010-d101.dtb
make m1n1                  # m1n1-idevice + monitor-stub
make rootfs                # out/rootfs.img (Alpine 3.24 aarch64, ext4)
make disk-linux            # out/disk-linux.img (GPT: rootfs + data)
make boot-image            # out/boot/m1n1-linux.macho

# phone in DFU, then:
sudo scripts/netboot/setup-usbnet.sh <usb-iface>   # static 192.168.137.2
sudo scripts/netboot/serve-nbd.sh out/disk-linux.img
sudo make prep             # iBSS + RestoreDeviceTree
sudo make boot
```

The phone's initramfs assigns itself `192.168.137.1`, runs `unudhcpd`, connects
to the host's `qemu-nbd` at `192.168.137.2:10809`, mounts `/dev/nbd0p1` and
`switch_root`s into Alpine. Log in on the USB ACM console (`/dev/ttyACM*`) as
`root` (no password during bring-up).

Addressing lives in `config/netboot.conf` and is used by both the host scripts
and the initramfs. If your host already owns `.1` on `192.168.137.0/24`, swap
`NB_PHONE_IP`/`NB_HOST_IP` there and rebuild the initramfs.

## Repository layout

```
docs/        boot chain, netboot, hardware notes, decisions
config/      kernel fragment, kernel cmdline, netboot addressing
patches/     tracked changes to vendored trees (applied after every sync)
vendor/      pinned upstream sources (git submodules)
initramfs/   first-stage init, NBD payloads
scripts/     host tooling (guarded; nothing touches the phone without asking)
out/         build artifacts (ignored)
```

## Current limits

- **No touch, WiFi, Bluetooth or internal storage** under Hoolock: the drivers
  exist upstream (`apple,z2` for Touch Bar panels, `brcmfmac`, `hci_bcm`,
  Apple NVMe), but the T8010 device tree has no SPI, PCIe, UART-BT or ANS2
  nodes, so nothing probes. Adding them is the next milestone
  (`docs/roadmap.md`). Corellium's `linux-sandcastle` is the reference for the
  register/GPIO/rail data, but its boot chain is not used here.
- **Display** is a simple framebuffer from the loader; there is no GPU/display
  controller driver yet.
- The legacy Android GSI payload is still present (`idroid_payload=android`);
  it is not the default and is slated for removal.

## Legal

Apple's firmware, the GSI, and disk images are not part of this repository.
`vendor/` content keeps its upstream licenses. Nothing here bypasses the phone's
hardware security; the boot chain relies on checkm8, which is an unpatchable
boot ROM bug on A10.
