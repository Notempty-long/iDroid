#!/bin/busybox sh
# Connect the GPT disk image from the host over USB Ethernet, mount Android's
# partitions, then hand off to Android's own init.
#
# Device: 172.16.42.1 (DHCP server, see init_functions.sh)
# Host:   172.16.42.2 (receives a lease; runs qemu-nbd on 10809)

NBD_HOST="${NBD_HOST:-172.16.42.2}"
NBD_PORT="${NBD_PORT:-10809}"
NBD_EXPORT="${NBD_EXPORT:-idroid}"

log() { echo "[idroid] $*"; }
die() { log "$*"; log "dropping to first-stage shell"; exec /bin/sh; }

# Find the gadget interface created by init_functions.sh.
find_iface() {
  local f
  for f in ncm rndis ecm; do
    [ -e "/sys/class/net/${f}0" ] && { echo "${f}0"; return; }
  done
  for f in usb0 eth0; do
    [ -e "/sys/class/net/$f" ] && { echo "$f"; return; }
  done
}

IFACE="$(find_iface)"
[ -n "$IFACE" ] || die "no USB network interface found"

log "waiting for carrier on $IFACE"
i=0
while [ "$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null)" != "1" ]; do
  i=$((i + 1))
  [ "$i" -ge 30 ] && die "no link on $IFACE after 30s (is the phone cable connected to a powered host?)"
  sleep 1
done

# The gadget address is set by start_unudhcpd (172.16.42.1). Make sure it stuck.
ip addr show dev "$IFACE" | grep -q '172\.16\.42\.1' || ip addr add 172.16.42.1/24 dev "$IFACE"

# devtmpfs normally creates /dev/nbd0 automatically, but populate /dev once in
# case the driver registered before devtmpfs was mounted.
mdev -s

log "connecting NBD $NBD_HOST:$NBD_PORT (export $NBD_EXPORT)"
# -N selects the export name. We build nbd-client without libnl, and its
# persist/reconnect monitor is netlink-only in 3.27.x, so -persist would be
# silently ignored. Do not pass it: a dropped link is handled by rebooting into
# the first-stage shell (idroid_debug=1) and reconnecting by hand.
if ! nbd-client "$NBD_HOST" "$NBD_PORT" /dev/nbd0 -N "$NBD_EXPORT"; then
  log "named export failed, retrying with the default export"
  nbd-client "$NBD_HOST" "$NBD_PORT" /dev/nbd0 || die "nbd-client failed (host: scripts/netboot/serve-nbd.sh)"
fi

# Let the kernel read the GPT and mdev create /dev/nbd0pN nodes.
mdev -s
i=0
while [ ! -b /dev/nbd0p2 ]; do
  i=$((i + 1))
  [ "$i" -ge 20 ] && die "/dev/nbd0p2 did not appear"
  sleep 1
  mdev -s
done

mkdir -p /dev/block/by-name
ln -sfn /dev/nbd0p1 /dev/block/by-name/vbmeta
ln -sfn /dev/nbd0p2 /dev/block/by-name/system
ln -sfn /dev/nbd0p3 /dev/block/by-name/vendor
ln -sfn /dev/nbd0p4 /dev/block/by-name/userdata

mount_one() {
  local dev="$1" dir="$2" opts="$3" fstype="${4:-ext4}"
  mkdir -p "$dir"
  if mount -t "$fstype" -o "$opts" "$dev" "$dir" 2>/dev/null; then
    log "mounted $dev on $dir ($opts)"
    return 0
  fi
  return 1
}

mount_one /dev/nbd0p2 /system "ro" \
  || die "cannot mount system (is the disk image formatted and is partition 2 the GSI?)"

# vendor is ours and may be empty during bring-up.
if ! mount_one /dev/nbd0p3 /vendor "ro"; then
  log "vendor partition missing or unformatted; continuing without it"
  mkdir -p /vendor
fi

# userdata is disposable. Format only when explicitly requested, never silently.
if ! mount_one /dev/nbd0p4 /data "rw,nosuid,nodev"; then
  if grep -q 'idroid_format_userdata=1' /proc/cmdline 2>/dev/null; then
    log "formatting userdata as ext4"
    mkfs.ext4 -F -L userdata /dev/nbd0p4 >/dev/null 2>&1 \
      && mount_one /dev/nbd0p4 /data "rw,nosuid,nodev" \
      || log "userdata format/mount failed"
  else
    log "userdata not formatted (add idroid_format_userdata=1 to format it)"
  fi
fi
[ -d /data ] && grep -q ' /data ' /proc/mounts || mount -t tmpfs tmpfs /data 2>/dev/null || true

# Android expects a metadata mount; use tmpfs until an encrypted metadata
# partition exists.
mkdir -p /metadata
mount -t tmpfs tmpfs /metadata 2>/dev/null || true
chmod 0771 /metadata 2>/dev/null || true

# Some GSI layouts expose product/system_ext inside system; make the standard
# top-level paths resolvable for init.
[ -e /product ] || ln -sfn /system/product /product
[ -e /system_ext ] || ln -sfn /system/system_ext /system_ext

log "handing off to Android init"
# selinux_setup loads the policy from /system and re-execs init second_stage.
# We deliberately do not use switch_root: Android's second stage expects the
# ramdisk root with /system, /vendor and /data mounted onto it.
exec /system/bin/init selinux_setup
