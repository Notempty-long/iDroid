#!/usr/bin/env bash
# Fetch Hoolock's minimal Alpine/musl aarch64 initramfs. It already contains a
# working USB gadget + DHCP setup, which we extend with NBD and Android mount
# logic instead of reimplementing configfs by hand.
#
# Pin the workflow commit and the artifact digest: nightly.link only serves the
# most recent run and artifacts expire. To rebuild from source:
#   git clone https://github.com/HoolockLinux/HoolockRD && git checkout <sha>
# and run its build.sh (Alpine minirootfs based).
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

repo_sha="${HOOLOCKRD_SHA:-2dce746e1165ad81b23e354773c19795dbd6b328}"
url="${INITRAMFS_URL:-https://nightly.link/HoolockLinux/HoolockRD/workflows/build/master/initramfs.gz.zip}"
sha256="${INITRAMFS_SHA256:-3ca7cf4a03ecfb02b2ae67e00ea19a60ce2dde983950bf20e6118181ea125b47}"

require_cmd curl
require_cmd unzip
require_cmd sha256sum

dest="$CACHE/initramfs/base"
zip="$dest/initramfs.gz.zip"
gz="$dest/initramfs.gz"

mkdir -p "$dest"
if [ ! -f "$zip" ]; then
  log "downloading HoolockRD initramfs (pinned $repo_sha)"
  curl -fL --retry 3 --retry-delay 2 -o "$zip.tmp" "$url"
  mv "$zip.tmp" "$zip"
fi

printf '%s  %s\n' "$sha256" "$zip" | sha256sum -c - || die "initramfs archive checksum mismatch"

if [ ! -f "$gz" ]; then
  unzip -p "$zip" initramfs.gz > "$gz.tmp"
  mv "$gz.tmp" "$gz"
fi

require_file "$gz"
printf 'base initramfs: %s (%s bytes gz)\n' "$gz" "$(stat -c%s "$gz")"
printf 'needs unpacking with: zcat %s | cpio -idm\n' "$gz"
