#!/bin/busybox sh
# Connect the rootfs image from the host over USB Ethernet and switch_root into
# it. The image is a plain GPT disk; partition 1 is the Linux rootfs.
#
# Link addressing comes from /etc/idroid-net.conf, which is generated from
# config/netboot.conf at build time.

[ -e /etc/idroid-net.conf ] && . /etc/idroid-net.conf

PHONE_IP="${NB_PHONE_IP:-192.168.137.1}"
HOST_IP="${NB_HOST_IP:-192.168.137.2}"
PREFIX="${NB_PREFIX:-24}"
NBD_HOST="${NBD_HOST:-$HOST_IP}"
NBD_PORT="${NBD_PORT:-${NB_NBD_PORT:-10809}}"
NBD_EXPORT="${NBD_EXPORT:-${NB_NBD_EXPORT:-idroid}}"
NBD_CLIENT="${NBD_CLIENT:-/usr/local/bin/nbd-client}"
NEWROOT="${NEWROOT:-/newroot}"

log() { echo "[idroid] $*"; }
die() {
  log "$*"
  log "dropping to first-stage shell (telnet $PHONE_IP:23 from the host)"
  exec /bin/sh
}

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

case "$PREFIX" in
  8) NETMASK=255.0.0.0 ;;
  16) NETMASK=255.255.0.0 ;;
  *) NETMASK=255.255.255.0 ;;
esac

log "waiting for carrier on $IFACE"
i=0
while [ "$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null)" != "1" ]; do
  i=$((i + 1))
  [ "$i" -ge 30 ] && die "no link on $IFACE after 30s (is the cable connected to a powered host?)"
  sleep 1
done

# start_unudhcpd already configured this, but re-assert it after re-enumeration.
ifconfig "$IFACE" 2>/dev/null | grep -q "addr:$PHONE_IP" \
  || ifconfig "$IFACE" "$PHONE_IP" netmask "$NETMASK" up

log "waiting for host $NBD_HOST to answer"
i=0
while ! ping -c 1 -W 1 "$NBD_HOST" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -ge 30 ] && die "host $NBD_HOST unreachable (is scripts/netboot/serve-nbd.sh running?)"
  sleep 1
done

mdev -s

log "connecting NBD $NBD_HOST:$NBD_PORT (export $NBD_EXPORT)"
if [ ! -x "$NBD_CLIENT" ]; then
  NBD_CLIENT="$(command -v nbd-client)" || die "nbd-client not found"
fi

# Do not pass -persist: this nbd-client was built without libnl, so the
# reconnect monitor is silently ignored.
if ! "$NBD_CLIENT" "$NBD_HOST" "$NBD_PORT" /dev/nbd0 -N "$NBD_EXPORT"; then
  log "named export failed, retrying with the default export"
  "$NBD_CLIENT" "$NBD_HOST" "$NBD_PORT" /dev/nbd0 || die "nbd-client failed (host: scripts/netboot/serve-nbd.sh)"
fi

mdev -s
i=0
while [ ! -b /dev/nbd0p1 ]; do
  i=$((i + 1))
  [ "$i" -ge 20 ] && die "/dev/nbd0p1 did not appear"
  sleep 1
  mdev -s
done

mkdir -p "$NEWROOT"
log "mounting /dev/nbd0p1 on $NEWROOT"
mount -t ext4 -o rw /dev/nbd0p1 "$NEWROOT" \
  || die "cannot mount rootfs (is partition 1 an ext4 image from scripts/build-alpine-rootfs.sh?)"

[ -x "$NEWROOT/sbin/init" ] || die "$NEWROOT/sbin/init missing (rootfs image looks incomplete)"

# Optional scratch partition.
if [ -b /dev/nbd0p2 ]; then
  mkdir -p "$NEWROOT/data"
  mount -t ext4 -o rw,nosuid,nodev /dev/nbd0p2 "$NEWROOT/data" 2>/dev/null \
    && log "mounted /dev/nbd0p2 on /data" \
    || log "partition 2 is not a usable ext4 data volume; skipping"
fi

mkdir -p "$NEWROOT/dev" "$NEWROOT/proc" "$NEWROOT/sys" "$NEWROOT/tmp" "$NEWROOT/run"
mount -t tmpfs -o mode=1777 tmpfs "$NEWROOT/tmp" 2>/dev/null || true
mount -t tmpfs -o mode=0755 tmpfs "$NEWROOT/run" 2>/dev/null || true

# Hand the addressing to the rootfs so it can bring the link back up later.
if [ -d "$NEWROOT/etc" ]; then
  cp /etc/idroid-net.conf "$NEWROOT/etc/idroid-net.conf" 2>/dev/null || true
fi

# switch_root deletes the initramfs; the nbd-client helper keeps running and
# keeps the NBD socket serviced, so the rootfs stays readable.
for d in dev proc sys; do
  mount -o move "/$d" "$NEWROOT/$d" 2>/dev/null \
    || mount -o rbind "/$d" "$NEWROOT/$d" 2>/dev/null \
    || log "could not carry over /$d"
done

log "switching root to /dev/nbd0p1"
exec switch_root "$NEWROOT" /sbin/init
