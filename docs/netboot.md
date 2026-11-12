# Netboot: Android over the USB Ethernet gadget

A10 has no usable internal storage under HoolockLinux, so Android's partitions
live on the host. The phone gets a normal block device (`/dev/nbd0`) over the
USB Ethernet gadget, so Android sees a GPT disk exactly as it would on a real
device.

## Topology

| Side | Interface | Address |
|---|---|---|
| Host | `usb0` (CDC-ECM/NCM host driver) | `172.16.42.2/24` (static) |
| Phone | `usb0`/`ncm0` (gadget) | `172.16.42.1/24` + DHCP server |

Hoolock's example initramfs (`init_functions.sh`) assigns `172.16.42.1` to the
gadget and runs `unudhcpd`, which leases `172.16.42.2` to the host. The host
therefore should **not** run a DHCP server; give it the static address instead.
Our first-stage initramfs keeps that behaviour and does not run `udhcpc`.

## Primary path: NBD

The host serves one raw GPT image over NBD. The image layout:

| # | Name | Size | Contents |
|---|---|---|---|
| 1 | `vbmeta` | 8 MiB | AVB metadata with verity/verification disabled |
| 2 | `system` | 6 GiB | GSI `system.img`, written verbatim |
| 3 | `vendor` | 1 GiB | minimal `vendor.img` (SELinux policy + `build.prop`; HALs later) |
| 4 | `userdata` | rest | ext4, created on first boot or pre-seeded |

`scripts/netboot/make-disk.sh` creates the table (and optionally writes a
`system.img` into partition 2).

### Host

```sh
scripts/build-vendor-image.sh            # out/vendor.img (split SELinux policy)
scripts/netboot/make-disk.sh out/disk.img cache/gsi/current/system.img
scripts/netboot/setup-usbnet.sh usb0     # static 172.16.42.2/24
scripts/netboot/serve-nbd.sh out/disk.img
```

`setup-usbnet.sh` only assigns the host address; the phone's initramfs is the
DHCP server on this link. `serve-nbd.sh` uses `qemu-nbd --persistent --shared=4`
on `172.16.42.2:10809`. It must be started only after `usb0` is up, otherwise
the bind fails.

### Device

The Android initramfs must, in order:

1. Load `nbd` (built into the kernel via `config/android.fragment`).
2. Bring up the gadget and start `unudhcpd` (already done by Hoolock's
   `init_functions.sh`); the device owns `172.16.42.1`.
3. `nbd-client 172.16.42.2 10809 /dev/nbd0 -N idroid`
   (or omit `-N` if the export is the default). Do not pass `-persist`: we build
   `nbd-client` without libnl and its reconnect monitor is netlink-only, so the
   flag is silently ignored in 3.27.x.
4. Export `by-name` symlinks for the GPT partitions (ueventd rules or a small
   first-stage helper): `system → nbd0p2`, `vendor → nbd0p3`,
   `userdata → nbd0p4`, `vbmeta → nbd0p1`.
5. Mount `system`/`vendor` read-only, `userdata` read-write, and hand off to
   Android's `init selinux_setup`.

Because the fstab and first-stage ramdisk are ours, absolute
`/dev/block/nbd0pN` paths are acceptable; `by-name` symlinks just make the
configuration look like a normal device and ease later migration.

## Why NBD and not NFS root

NFS root is simpler for kernel debugging, but Android expects block devices for
`system`, `vendor`, `userdata`, `vbmeta`, and dm-verity/overlayfs. NBD matches
those semantics and lets the same images be loop-mounted on the host. Keep an
NFS-root ramdisk as a **fallback** for early kernel/init debugging only.

## Bandwidth and safety

- USB 2.0 + NBD is sufficient for bring-up; expect slow first boot.
- The gadget is host-local. Do not bridge `usb0` to a physical LAN.
- `qemu-nbd` writes are not power-fail safe. Keep the image backed up and expect
  to re-image `userdata` often.

## Debugging the first stage

Add `idroid_debug=1` to `config/cmdline` (or the m1n1 bootargs) to stop in the
ramdisk shell instead of starting Android. The phone also runs `telnetd` on
`172.16.42.1:23` whenever the gadget is up.

The console is `tty0`; if the display is not initialized yet, use the USB
serial console exposed by Hoolock's initramfs (`/dev/ttyACM*` on the host).

## Fallback: NFS root

If the image gets corrupted or NBD is not yet wired up, boot Linux with:

```
root=/dev/nfs nfsroot=172.16.42.2:/srv/idroid/rootfs,vers=4.2 rw \
ip=172.16.42.1::172.16.42.2:255.255.255.0::usb0:off
```

This is a Linux rootfs, not Android; it is for validating the gadget, DHCP,
and display path.
