#!/usr/bin/env bash
# Build the Linux rootfs image that is served over NBD as /dev/nbd0p1.
#
# The image is a plain ext4 filesystem populated from Alpine's aarch64
# minirootfs (musl, BusyBox) plus a small iDroid bootstrap:
#   - BusyBox init runs /etc/init.d/rcS, then gettys on ttyGS0 and tty0
#   - root logs in without a password (bring-up only; the console is the
#     physically attached USB link)
#
# Ownership is applied inside a user namespace so this works unprivileged.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

ALPINE_VERSION="${ALPINE_VERSION:-3.24.4}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"

img="${1:-$OUT/rootfs.img}"
size="${2:-4G}"
tree="$OUT/rootfs/tree"
cache="$CACHE/rootfs"
tarball="$cache/alpine-minirootfs-$ALPINE_VERSION-aarch64.tar.gz"

require_cmd tar
require_cmd mke2fs
require_cmd curl
require_cmd sha256sum
require_file "$ROOT/config/netboot.conf" "repository is incomplete"

if [ ! -f "$tarball" ]; then
  mkdir -p "$cache"
  log "downloading Alpine $ALPINE_VERSION minirootfs"
  curl -fsSL -o "$tarball" \
    "$ALPINE_MIRROR/v$ALPINE_VERSION/releases/aarch64/alpine-minirootfs-$ALPINE_VERSION-aarch64.tar.gz"
fi
if [ ! -f "$tarball.sha256" ]; then
  curl -fsSL -o "$tarball.sha256" \
    "$ALPINE_MIRROR/v$ALPINE_VERSION/releases/aarch64/alpine-minirootfs-$ALPINE_VERSION-aarch64.tar.gz.sha256"
fi
log "verifying $(basename "$tarball")"
(cd "$cache" && sha256sum -c "$(basename "$tarball").sha256" >/dev/null) \
  || die "Alpine minirootfs checksum mismatch"

log "populating $tree"
rm -rf "$tree"
mkdir -p "$tree"

nbd="${NBD_CLIENT:-$CACHE/nbd-client/3.27.1/nbd-client}"

# Run extraction, configuration and mke2fs under fakeroot: files are created
# as "root" and the ownership is recorded as uid/gid 0 in the image.
if command -v fakeroot >/dev/null 2>&1; then
  NS_CMD=(fakeroot --)
elif unshare -r --map-root-user true 2>/dev/null; then
  NS_CMD=(unshare -r --map-root-user)
else
  die "need fakeroot or 'unshare -r' to build a root-owned image"
fi

"${NS_CMD[@]}" bash -euo pipefail -s -- \
  "$tree" "$tarball" "$ROOT/config/netboot.conf" "$nbd" "$img" "$size" <<'INNER'
tree="$1"
tarball="$2"
conf="$3"
nbd="$4"
img="$5"
size="$6"

tar -xzf "$tarball" -C "$tree"

# --- console ---------------------------------------------------------------
mkdir -p "$tree/etc/init.d"
cat >"$tree/etc/inittab" <<'EOF'
# iDroid busybox init
::sysinit:/etc/init.d/rcS
ttyGS0::respawn:/sbin/getty -L ttyGS0 115200 vt100
tty0::respawn:/sbin/getty -L tty0 115200 vt100
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/poweroff
EOF

cat >"$tree/etc/init.d/rcS" <<'EOF'
#!/bin/sh
# iDroid rootfs bootstrap (busybox init; no OpenRC in the minirootfs).
[ -r /etc/idroid-net.conf ] && . /etc/idroid-net.conf

busybox mountpoint -q /proc || mount -t proc proc /proc
busybox mountpoint -q /sys  || mount -t sysfs sysfs /sys
busybox mountpoint -q /dev  || mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm /tmp /run /data
busybox mountpoint -q /dev/pts || mount -t devpts devpts /dev/pts
busybox mountpoint -q /tmp || mount -t tmpfs -o mode=1777 tmpfs /tmp
busybox mountpoint -q /run || mount -t tmpfs -o mode=0755 tmpfs /run
busybox hostname -F /etc/hostname 2>/dev/null

# The initramfs configured the link; re-assert it after re-enumeration.
if [ -n "${NB_PHONE_IP:-}" ]; then
  for i in ncm0 rndis0 ecm0 usb0 eth0; do
    [ -e "/sys/class/net/$i" ] || continue
    ip addr show dev "$i" 2>/dev/null | grep -q "inet $NB_PHONE_IP/" ||
      ip addr add "$NB_PHONE_IP/${NB_PREFIX:-24}" dev "$i"
  done
fi

echo "iDroid rootfs: $(cat /etc/alpine-release 2>/dev/null) on $(uname -r)"
EOF
chmod 0755 "$tree/etc/init.d/rcS"

# --- base configuration ----------------------------------------------------
echo idroid >"$tree/etc/hostname"
cat >"$tree/etc/hosts" <<'EOF'
127.0.0.1 localhost idroid
::1       localhost
EOF

cat >"$tree/etc/fstab" <<'EOF'
/dev/nbd0p1 /      ext4  rw,relatime              0 1
/dev/nbd0p2 /data  ext4  rw,nosuid,nodev,noauto   0 0
proc        /proc  proc  defaults                  0 0
sysfs       /sys   sysfs defaults                  0 0
devtmpfs    /dev   devtmpfs mode=0755              0 0
tmpfs       /tmp   tmpfs mode=1777                 0 0
EOF

cat >"$tree/etc/motd" <<'EOF'
iDroid: Alpine Linux on an iPhone 7 (t8010), rootfs served over NBD.

  uname -a            kernel and version
  ip addr             USB link address (default 192.168.137.1)
  poweroff            stop the phone
EOF

cat >"$tree/etc/profile.d/00-idroid.sh" <<'EOF'
export PS1='idroid:\w# '
EOF

# Root login on the USB console, bring-up only.
sed -i 's/^root:[^:]*:/root::/' "$tree/etc/shadow"
grep -qx ttyGS0 "$tree/etc/securetty" 2>/dev/null || echo ttyGS0 >>"$tree/etc/securetty"
grep -qx tty0 "$tree/etc/securetty" 2>/dev/null || echo tty0 >>"$tree/etc/securetty"

cp "$conf" "$tree/etc/idroid-net.conf"
chmod 0644 "$tree/etc/idroid-net.conf"
if [ -x "$nbd" ]; then
  mkdir -p "$tree/usr/local/bin"
  cp "$nbd" "$tree/usr/local/bin/nbd-client"
fi

# --- filesystem image ------------------------------------------------------
rm -f "$img"
truncate -s "$size" "$img"
mke2fs -q -F -t ext4 -b 4096 -m 0 -d "$tree" -L idroid-root "$img"
INNER

ok "rootfs image: ${img#"$ROOT"/} ($(stat -c%s "$img") bytes, Alpine $ALPINE_VERSION)"
