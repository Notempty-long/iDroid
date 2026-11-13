#!/usr/bin/env bash
# Assemble the first-stage ramdisk.
#
# Base: Hoolock's Alpine/musl initramfs (USB gadget + DHCP already works).
# Added: static nbd-client, our /init, the NBD payloads (/linux.sh,
# /android.sh) and the baked netboot addressing (/etc/idroid-net.conf).
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

require_cmd cpio
require_cmd gzip
require_cmd zcat

base="$CACHE/initramfs/base/initramfs.gz"
root="$OUT/initramfs/root"
out="$OUT/initramfs/initramfs.gz"

require_file "$base" "run scripts/fetch-initramfs.sh"
require_file "$ROOT/initramfs/init" "repository is incomplete"
require_file "$ROOT/initramfs/linux.sh" "repository is incomplete"
require_file "$ROOT/initramfs/android.sh" "repository is incomplete"
require_file "$ROOT/config/netboot.conf" "repository is incomplete"

# Prefer the pinned static build; fall back to an explicit override.
nbd="${NBD_CLIENT:-$CACHE/nbd-client/3.27.1/nbd-client}"
require_file "$nbd" "run scripts/fetch-nbd-client.sh"

rm -rf "$root"
mkdir -p "$root"
log "unpacking $(basename "$base")"
(cd "$root" && zcat "$base" | cpio -idm --quiet)

# Keep the original around for debugging (not used at boot).
if [ -f "$root/init" ]; then
  mv "$root/init" "$root/init.hoolock"
fi

install -m 0755 "$ROOT/initramfs/init" "$root/init"
install -m 0755 "$ROOT/initramfs/linux.sh" "$root/linux.sh"
install -m 0755 "$ROOT/initramfs/android.sh" "$root/android.sh"
mkdir -p "$root/etc" "$root/usr/local/bin"
install -m 0644 "$ROOT/config/netboot.conf" "$root/etc/idroid-net.conf"
install -m 0755 "$nbd" "$root/usr/local/bin/nbd-client"

mkdir -p "$OUT/initramfs"
log "packing initramfs"
(cd "$root" && find . -print0 \
  | cpio --null -o -H newc --owner=0:0 --reproducible --quiet \
  | gzip -9) > "$out.tmp"
mv "$out.tmp" "$out"

zcat "$out" | cpio -t --quiet >/dev/null 2>&1 || die "repacked initramfs is not readable"
require_file "$root/usr/local/bin/nbd-client"
[ -x "$root/init" ] || die "init is not executable in the root tree"
[ -f "$root/etc/idroid-net.conf" ] || die "netboot config missing from the root tree"

ok "initramfs: ${out#"$ROOT"/} ($(stat -c%s "$out") bytes)"
ok "  /init, /linux.sh, /android.sh, /usr/local/bin/nbd-client installed"
ok "  link: $(sed -n 's/^NB_PHONE_IP=//p' "$root/etc/idroid-net.conf") (phone) -> $(sed -n 's/^NB_HOST_IP=//p' "$root/etc/idroid-net.conf") (host)"
