#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib.sh"

img="${1:-$OUT/disk.img}"
size="${2:-16G}"
system="${3:-${SYSTEM_IMG:-}}"

require_cmd sgdisk
require_cmd dd

system_size="${SYSTEM_SIZE:-6G}"
vendor_size="${VENDOR_SIZE:-1G}"
vbmeta_size="${VBMETA_SIZE:-8M}"

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
  --new=1:0:+"$vbmeta_size" --typecode=1:8300 --change-name=1:vbmeta \
  --new=2:0:+"$system_size" --typecode=2:8300 --change-name=2:system \
  --new=3:0:+"$vendor_size" --typecode=3:8300 --change-name=3:vendor \
  --new=4:0:0               --typecode=4:8300 --change-name=4:userdata \
  "$img" >/dev/null

if [ -n "$system" ]; then
  require_file "$system"
  start="$(sgdisk -i 2 "$img" | sed -n 's/^First sector: \([0-9][0-9]*\).*/\1/p')"
  [ -n "$start" ] || die "could not read system partition offset"

  sectors="$(sgdisk -i 2 "$img" | sed -n 's/^Partition size: \([0-9][0-9]*\) sectors.*/\1/p')"
  [ -n "$sectors" ] || die "could not read system partition size"
  max_bytes=$((sectors * 512))
  system_bytes="$(stat -c%s "$system")"
  if [ "$system_bytes" -gt "$max_bytes" ]; then
    die "$system is $system_bytes bytes but partition 2 is $max_bytes bytes; raise SYSTEM_SIZE"
  fi

  log "writing $system into partition 2 at sector $start"
  dd if="$system" of="$img" bs=512 seek="$start" conv=notrunc,sparse status=progress
fi

sgdisk -p "$img" >&2
ok "disk image: ${img#"$ROOT"/}"
warn "vendor/userdata are empty partitions; build/format them before booting Android"
