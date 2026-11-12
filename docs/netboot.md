# Netboot: Android over the USB Ethernet gadget

A10 has no usable internal storage under HoolockLinux, so Android's partitions
live on the host. The phone gets a normal block device (`/dev/nbd0`) over the
USB Ethernet gadget, so Android sees a GPT disk exactly as it would on a real
device.

## Topology

| Side | Interface | Address |
|---|---|---|
| Host | `usb0` (CDC-ECM host driver) | `172.16.42.2/24` + DHCP server |
| Phone | `usb0` (gadget) | `172.16.42.1/24` (DHCP) |

Hoolock's example initramfs uses `172.16.42.1` for the device and
`172.16.42.2` for the host. Android's EthernetService is a DHCP client, so the
host must run a DHCP server on `usb0`.

## Primary path: NBD

The host serves one raw GPT image over NBD. The image layout:

| # | Name | Size | Contents |
|---|---|---|---|
| 1 | `vbmeta` | 8 MiB | AVB metadata with verity/verification disabled |
| 2 | `system` | 6 GiB | GSI `system.img`, written verbatim |
| 3 | `vendor` | 1 GiB | our `vendor.img` (HALs, firmware, policy, `hx-touchd`) |
| 4 | `userdata` | rest | ext4, created on first boot or pre-seeded |

`scripts/netboot/make-disk.sh` creates the table (and optionally writes a
`system.img` into partition 2).

### Host

```sh
scripts/netboot/setup-usbnet.sh usb0     # 172.16.42.2/24 + dnsmasq
scripts/netboot/serve-nbd.sh out/disk.img
```

`serve-nbd.sh` uses `qemu-nbd --persistent --shared=4` on `172.16.42.2:10809`.
It must be started only after `usb0` is up, otherwise the bind fails.

### Device

The Android initramfs must, in order:

1. Load `nbd` (built into the kernel via `config/android.fragment`).
2. `udhcpc -i usb0` (or Android's `init` DHCP path) to get `172.16.42.1`.
3. `nbd-client 172.16.42.2 10809 /dev/nbd0 -persist -N idroid`
   (or omit `-N` if the export is the default).
4. Export `by-name` symlinks for the GPT partitions (ueventd rules or a small
   first-stage helper): `system → nbd0p2`, `vendor → nbd0p3`,
   `userdata → nbd0p4`, `vbmeta → nbd0p1`.
5. Mount `system`/`vendor` read-only, `userdata` read-write, and hand off to
   Android's first-stage init via the fstab we control.

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

## Fallback: NFS root

If the image gets corrupted or NBD is not yet wired up, boot Linux with:

```
root=/dev/nfs nfsroot=172.16.42.2:/srv/idroid/rootfs,vers=4.2 rw \
ip=172.16.42.1::172.16.42.2:255.255.255.0::usb0:off
```

This is a Linux rootfs, not Android; it is for validating the gadget, DHCP,
and display path.
