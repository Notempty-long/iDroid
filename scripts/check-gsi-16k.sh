#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

img="${1:-$CACHE/gsi/current/system.img}"
require_file "$img" "run scripts/fetch-gsi.sh"
require_cmd debugfs
require_cmd readelf

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

target=""
for candidate in /system/lib64/libc.so /lib64/libc.so /system/bin/init /init; do
  if debugfs -R "stat $candidate" "$img" >/dev/null 2>&1; then
    target="$candidate"
    break
  fi
done
[ -n "$target" ] || die "no known ELF found in $img (ext4 expected)"

out="$tmp/$(basename "$target")"
debugfs -R "dump $target $out" "$img" >/dev/null 2>&1
[ -s "$out" ] || die "failed to extract $target from $img"

max=0
while read -r align; do
  [ -n "$align" ] || continue
  value=$((align))
  if [ "$value" -gt "$max" ]; then
    max=$value
  fi
done < <(readelf -lW "$out" | awk '$1 == "LOAD" { print $NF }')

[ "$max" -gt 0 ] || die "no LOAD segments in $target"

printf 'image:      %s\n' "$img"
printf 'ELF:        %s\n' "$target"
printf 'max p_align: 0x%x (%d bytes)\n' "$max" "$max"

if [ "$max" -lt 16384 ]; then
  die "GSI is not 16 KiB compatible (need >= 0x4000); do not expect a boot"
fi

if command -v dumpe2fs >/dev/null 2>&1; then
  block="$(dumpe2fs -h "$img" 2>/dev/null | awk -F: '/Block size/ { gsub(/ /, "", $2); print $2 }' || true)"
  [ -n "$block" ] && printf 'ext4 block:  %s bytes (independent of page size)\n' "$block"
fi

ok "GSI looks 16 KiB compatible"
