# Netboot: Linux from NBD over the USB Ethernet gadget

Hoolock's T8010 device tree exposes no internal block device, so the rootfs
lives on the host. The phone gets `/dev/nbd0` over the USB Ethernet gadget and
`switch_root`s into a normal ext4 rootfs on `/dev/nbd0p1`.

## Topology

| Side | Interface | Address |
|---|---|---|
| Host | `usb0` (CDC-ECM/NCM host driver) | `192.168.137.2/24` (static) |
| Phone | `ncm0`/`usb0` (gadget) | `192.168.137.1/24` + DHCP server |

Both addresses come from `config/netboot.conf`; the same file is baked into the
initramfs as `/etc/idroid-net.conf` and sourced by the host scripts, so there is
one source of truth.

Hoolock's `init_functions.sh` assigns the phone address and runs `unudhcpd`,
which leases the host address. The host must **not** run a DHCP server on this
interface; `scripts/netboot/setup-usbnet.sh` gives it the static address.

If your host already owns `.1` on this subnet (Windows ICS uses
`192.168.137.1`), swap `NB_PHONE_IP` and `NB_HOST_IP` in `config/netboot.conf`
and rebuild the initramfs (`make initramfs boot-image`).

## Disk layout

`scripts/netboot/make-linux-disk.sh` creates:

| # | Name | Size | Contents |
|---|---|---|---|
| 1 | `rootfs` | 4 GiB | ext4, written verbatim from `out/rootfs.img` |
| 2 | `data` | rest | ext4, mounted at `/data` when present |

`out/rootfs.img` is built by `scripts/build-alpine-rootfs.sh` from Alpine's
aarch64 minirootfs (BusyBox init, no OpenRC) plus:

- `/etc/init.d/rcS` — mounts `/proc`, `/sys`, `/dev`, tmpfs and re-asserts the
  USB link address
- gettys on `ttyGS0` (USB ACM console) and `tty0`
- `root` unlocked for console login (bring-up only)
- `/etc/idroid-net.conf` so the rootfs knows the link addresses

## Host

```sh
make rootfs                                     # out/rootfs.img
make disk-linux                                 # out/disk-linux.img
sudo scripts/netboot/setup-usbnet.sh <iface>    # static 192.168.137.2/24
sudo scripts/netboot/serve-nbd.sh out/disk-linux.img
```

`serve-nbd.sh` runs `qemu-nbd --persistent --shared=4` on
`192.168.137.2:10809` with export name `idroid`. It must be started only after
the host interface is up, otherwise the bind fails.

If the host runs a firewall, allow inbound traffic from the link subnet. With
ufw, `setup-usbnet.sh` adds this automatically; otherwise:

```sh
sudo ufw allow from 192.168.137.0/24 comment 'iDroid USB netboot'
```

ICMP is usually allowed by default, so the link still pings while TCP SYNs to
`10809` are dropped; `nbd-client` then blocks in `connect()` with no output.

## Device

`initramfs/init` does, in order:

1. `setup_usb_network` — create and bind the NCM function **on its own**.
2. `start_unudhcpd` — assign `192.168.137.1`, lease `192.168.137.2`.
3. Add the ACM function and rebind the UDC once, so `console=ttyGS0` works.
4. `exec /linux.sh` (unless `idroid_debug=1` or `idroid_payload=android`).

Binding NCM and ACM together before the first UDC bind makes the host's
`cdc_ncm` TX path stall (`NETDEV WATCHDOG: transmit queue 0 timed out`, ARP
never resolves) even though the initial DHCP exchange succeeds. Keep the
ordering above.

`initramfs/linux.sh` then:

1. Waits for carrier and for `192.168.137.2` to answer.
2. `nbd-client 192.168.137.2 10809 /dev/nbd0 -N idroid`.
3. Mounts `/dev/nbd0p1` on `/newroot` (and `nbd0p2` on `/data` if present).
4. Moves `/dev`, `/proc`, `/sys` into the new root.
5. `switch_root /newroot /sbin/init`.

Do not pass `-persist`: the pinned `nbd-client` 3.27.1 is built without libnl
and its reconnect monitor is netlink-only, so the flag is silently ignored. The
`nbd-client` helper keeps running after `switch_root` and services the socket.

## Debugging

The gadget always exposes an ACM serial with the kernel console
(`console=ttyGS0 console=tty0`). Capture it across resets and re-enumeration:

```sh
sudo nohup scripts/netboot/capture-acm.sh /tmp/idroid-acm.log >/dev/null 2>&1 &
```

`idroid_debug=1` in `config/cmdline` stops in the first-stage shell instead of
handing off. The first stage also runs `telnetd` on `192.168.137.1:23`, so the
host can reach the shell over the link even when the ACM port is stuck.

From the phone side:

```sh
ip addr                       # gadget address
nbd-client -c /dev/nbd0       # connected pid (0 when disconnected)
mount | grep nbd              # rootfs mounted at /newroot
```

If `/dev/nbd0p1` never appears, check the host's `qemu-nbd` output and the
firewall rule above.

## Legacy Android payload

`initramfs/android.sh` still boots the Android 16 GSI image (GPT: vbmeta /
system / vendor / userdata) when `idroid_payload=android` is on the kernel
command line. It is kept only for reference while the Linux path stabilises and
is not built by the default targets.
