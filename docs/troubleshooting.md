# Troubleshooting

## Phone not detected in DFU

- `lsusb | grep 05ac:1227` must show the DFU device.
- Use a direct, data-capable cable; avoid hubs and charge-only cables.
- Re-enter DFU: Power + Volume Down 10 s, release Power, keep Volume Down ~5 s.
- On Linux, check `dmesg` for USB resets; try another port/controller.

## `remote_boot prep` fails during checkm8

- A10 checkm8 can take several attempts; re-enter DFU and retry.
- The tool must run as root and needs `gaster` built (`libusb-1.0` headers).
- If it tries to query CPID/MODEL, the patch did not apply:
  `scripts/apply-patches.sh` then retry.
- If it attempts an iBEC stage, the hard-coded `0x8010` was not picked up
  (`0x8010` is single-stage).

## Cable replug messages

`remote_boot` prints "a cable replug may be required" after iBSS on some hosts.
Unplug/replug the Lightning cable when it stalls, then let the script continue.

## Kernel does not boot after m1n1

- Confirm `out/boot/m1n1-linux.macho` contains: m1n1 Mach-O, `chosen.bootargs=…`,
  DTB, `Image.gz` (and optionally the initramfs). `scripts/build-m1n1-blob.sh`
  validates the DTB magic.
- Check `t8010-d101.dtb` matches the phone (`d101ap`); a `d10`/`d11` DTB will
  not drive this panel.
- Try a minimal cmdline (`console=tty0 loglevel=8`) to rule out Android params.
- Verify the kernel was built with `ARCH=arm64 LLVM=1` and
  `CONFIG_ARM64_16K_PAGES=y`.

## No `usb0` on the host

- The gadget is configured in the initramfs (configfs + `g_ether`/ECM).
- Check the device log over the gadget serial; if there is no gadget at all the
  initramfs did not reach configfs setup.
- Host: `dmesg | tail`, `ip link`; the interface may appear as `enx…` (MAC-based
  name) instead of `usb0` — pass the real name to `scripts/netboot/setup-usbnet.sh`.

## DHCP/NBD

- Device must get `192.168.137.1`; host must be `192.168.137.2` (both from
  `config/netboot.conf`).
- Start order: `setup-usbnet.sh` **then** `serve-nbd.sh` (qemu-nbd binds to the
  host address).
- `ss -lunp | grep 10809` confirms the export is listening.
- Firewall: allow TCP 10809 on the USB interface only.
- `nbd-client` errors usually mean the device has no route to the host. Test
  with `ping 192.168.137.2`.

## Linux rootfs boot

- Logs go to the gadget serial (`console=ttyGS0`) and the framebuffer console.
- If `/dev/nbd0p1` is missing, check the NBD connection and the GPT: run
  `sgdisk -p out/disk-linux.img` on the host.
- `switch_root` failures usually mean `nbd0p1` is not ext4 or has no
  `/sbin/init`; rebuild with `make rootfs disk-linux`.
- A rootfs that mounts but immediately dies usually means the kernel lacks a
  required option; check `out/kernel/config` (ext4, devtmpfs, NBD are built in).
- Keep the ACM capture running; the first-stage shell is also reachable over
  `telnet 192.168.137.1` when the link is healthy.

## Display

- A blank panel with a live kernel usually means the DTB/panel node mismatch or
  the backlight is off. Hoolock supports main display since 6.13 and brightness
  since 6.15; check `dmesg` for the display/backlight drivers.
- Software composition is slow; a black screen with a responsive `adb` can be
  SurfaceFlinger waiting on a graphics allocator.

## Touch

- `hx-touchd` needs the correct I2C bus and address for `d101ap`; a wrong bus
  reads garbage or times out.
- Verify `/dev/uinput` exists and Android sees an input device
  (`getevent -l`).
- Do not run two touch daemons: both will inject events.

## Resetting

- `out/` and `cache/` are disposable.
- `scripts/vendor-sync.sh` restores vendored trees and re-applies patches.
- If a submodule is wedged: `git submodule update --init --recursive --force`
  (this discards local submodule changes — patches are reapplied afterwards).
