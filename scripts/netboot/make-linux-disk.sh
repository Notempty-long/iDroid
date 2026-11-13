#!/usr/bin/env bash
# Create the Linux netboot disk: p1 = rootfs (written verbatim), p2 = data.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib.sh"

img="${1:-$OUT/disk-linux.img}"
size="${2:-16G}"
rootfs="${3:-${ROOTFS_IMG:-$OUT/rootfs.img}}"
rootfs_size="${ROOTFS_SIZE:-4G}"

require_cmd sgdisk
require_cmd dd
require_cmd truncate
require_cmd mke2fs
require_file "$rootfs" "run scripts/build-alpine-rootfs.sh"

if [ -e "$img" ]; then
  if [ "${FORCE:-0}" = "1" ]; then
    rm -f "$img"
  else
    die "$img exists (set FORCE=1 to recreate)"
  fi
fi

mkdir -p "$(dirname "$img")"
log "creating sparse $size image at ${img#"$ROOT"/}"
truncate -s "$size" "$img"

sgdisk --clear --set-alignment=2048 \
  --new=1:0:+"$rootfs_size" --typecode=1:8300 --change-name=1:rootfs \
  --new=2:0:0                --typecode=2:8300 --change-name=2:data \
  "$img" >/dev/null

part_field() {
  sgdisk -i "$1" "$img" | sed -n "s/^$2: \([0-9][0-9]*\).*/\1/p"
}

start="$(part_field 1 'First sector')"
[ -n "$start" ] || die "could not read partition 1 offset"
sectors="$(part_field 1 'Partition size')"
[ -n "$sectors" ] || die "could not read partition 1 size"
bytes="$(stat -c%s "$rootfs")"
max_bytes=$((sectors * 512))
if [ "$bytes" -gt "$max_bytes" ]; then
  die "$rootfs is $bytes bytes but partition 1 is $max_bytes bytes; raise ROOTFS_SIZE"
fi

log "writing $rootfs into partition 1 at sector $start"
dd if="$rootfs" of="$img" bs=512 seek="$start" conv=notrunc,sparse status=none

# data stays disposable; format it now so a fresh boot has a writable /data.
start="$(part_field 2 'First sector')"
sectors="$(part_field 2 'Partition size')"
[ -n "$start" ] && [ -n "$sectors" ] || die "could not read partition 2 geometry"
blocks=$((sectors * 512 / 4096))
log "formatting partition 2 (data) as ext4"
mke2fs -q -F -t ext4 -b 4096 -m 0 -E "offset=$((start * 512)),nodiscard" \
  -L idroid-data "$img" "$blocks"

sgdisk -p "$img" >&2
ok "disk image: ${img#"$ROOT"/}"
