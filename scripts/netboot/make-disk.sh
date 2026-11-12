#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib.sh"

img="${1:-$OUT/disk.img}"
size="${2:-16G}"
system="${3:-${SYSTEM_IMG:-}}"

require_cmd sgdisk
require_cmd dd

format_vendor="${FORMAT_VENDOR:-1}"
format_userdata="${FORMAT_USERDATA:-1}"
vendor_written=0
if [ "$format_vendor" = "1" ] || [ "$format_userdata" = "1" ]; then
  require_cmd mke2fs
fi

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

write_part() {
  local num="$1" file="$2" start sectors max_bytes bytes
  require_file "$file"
  start="$(sgdisk -i "$num" "$img" | sed -n 's/^First sector: \([0-9][0-9]*\).*/\1/p')"
  [ -n "$start" ] || die "could not read partition $num offset"

  sectors="$(sgdisk -i "$num" "$img" | sed -n 's/^Partition size: \([0-9][0-9]*\) sectors.*/\1/p')"
  [ -n "$sectors" ] || die "could not read partition $num size"
  max_bytes=$((sectors * 512))
  bytes="$(stat -c%s "$file")"
  if [ "$bytes" -gt "$max_bytes" ]; then
    die "$file is $bytes bytes but partition $num is $max_bytes bytes; raise the partition size"
  fi

  log "writing $file into partition $num at sector $start"
  dd if="$file" of="$img" bs=512 seek="$start" conv=notrunc,sparse status=progress
}

if [ -n "$system" ]; then
  write_part 2 "$system"
fi

# Prefer a real vendor image (SELinux policy, build.prop) over an empty ext4.
vendor="${VENDOR_IMG:-$OUT/vendor.img}"
if [ -f "$vendor" ]; then
  write_part 3 "$vendor"
  format_vendor=0
  vendor_written=1
fi

sgdisk -p "$img" >&2

# Format inside the image without loop devices, so this works unprivileged.
# 4096-byte ext4 blocks are independent of the kernel's 16 KiB page size.
format_part() {
  local num="$1" label="$2" start sectors blocks
  start="$(sgdisk -i "$num" "$img" | sed -n 's/^First sector: \([0-9][0-9]*\).*/\1/p')"
  sectors="$(sgdisk -i "$num" "$img" | sed -n 's/^Partition size: \([0-9][0-9]*\) sectors.*/\1/p')"
  [ -n "$start" ] && [ -n "$sectors" ] || die "could not read partition $num geometry"
  blocks=$((sectors * 512 / 4096))
  log "formatting partition $num ($label) as ext4 at offset $((start * 512))"
  mke2fs -q -F -t ext4 -b 4096 -m 0 -E "offset=$((start * 512)),nodiscard" \
    -L "$label" "$img" "$blocks"
}

if [ "$format_vendor" = "1" ]; then
  format_part 3 vendor
fi
if [ "$format_userdata" = "1" ]; then
  format_part 4 userdata
fi

ok "disk image: ${img#"$ROOT"/}"
if [ "$format_userdata" != "1" ]; then
  warn "userdata is not formatted; boot with idroid_format_userdata=1 or re-run with FORMAT_USERDATA=1"
fi
if [ "$format_vendor" != "1" ] && [ "$vendor_written" != "1" ]; then
  warn "vendor is not formatted; Android may fail to mount it (run scripts/build-vendor-image.sh)"
fi
