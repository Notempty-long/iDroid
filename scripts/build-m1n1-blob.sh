#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

require_cmd cat
require_cmd printf
require_cmd xxd

m1n1_dir="$CACHE/m1n1"
dtb="${DTB:-$OUT/kernel/${DEVICE_DTB:-t8010-d101.dtb}}"
image="${IMAGE_GZ:-$OUT/kernel/Image.gz}"
initramfs="${INITRAMFS:-}"

require_file "$m1n1_dir/m1n1-idevice.macho" "run scripts/fetch-m1n1.sh"
require_file "$m1n1_dir/monitor-stub.macho" "run scripts/fetch-m1n1.sh"
require_file "$dtb" "run scripts/build-kernel.sh"
require_file "$image" "run scripts/build-kernel.sh"

magic="$(xxd -p -l 4 "$dtb")"
[ "$magic" = "d00dfeed" ] || die "$dtb is not a flattened device tree (magic $magic)"

cmdline="${CMDLINE:-$(tr '\n' ' ' < "$ROOT/config/cmdline" | sed -e 's/[[:space:]]\{1,\}/ /g' -e 's/^ //' -e 's/ $//')}"
[ -n "$cmdline" ] || die "empty kernel command line"

if [ -n "$initramfs" ]; then
  require_file "$initramfs" "built Android first-stage ramdisk"
fi

mkdir -p "$OUT/boot"
tmp="$OUT/boot/.m1n1-linux.macho.tmp"
{
  cat "$m1n1_dir/m1n1-idevice.macho"
  printf 'chosen.bootargs=%s\n' "$cmdline"
  cat "$dtb"
  cat "$image"
  if [ -n "$initramfs" ]; then
    cat "$initramfs"
  fi
} > "$tmp"
mv "$tmp" "$OUT/boot/m1n1-linux.macho"

install -m 0644 "$m1n1_dir/monitor-stub.macho" "$OUT/boot/monitor-stub.macho"

ok "boot bundle: ${OUT#"$ROOT"/}/boot/m1n1-linux.macho"
ok "stub:        ${OUT#"$ROOT"/}/boot/monitor-stub.macho"
if [ -z "$initramfs" ]; then
  warn "no INITRAMFS supplied: Linux will boot, but Android needs a first-stage ramdisk"
fi
