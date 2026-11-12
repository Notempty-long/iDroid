#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

require_cmd curl
require_cmd unzip
require_cmd sha256sum

url="${M1N1_URL:-https://nightly.link/hoolocklinux/m1n1/workflows/build/idevice/m1n1.zip}"
dest="$CACHE/m1n1"
zip="$dest/m1n1.zip"

mkdir -p "$dest"
log "downloading m1n1 image: $url"
curl -fL --retry 3 --retry-delay 2 -o "$zip.tmp" "$url"
mv "$zip.tmp" "$zip"

archive_sha="$(sha256sum "$zip" | awk '{print $1}')"
printf '%s  m1n1.zip\n' "$archive_sha" > "$dest/m1n1.sha256"

if [ -n "${M1N1_SHA256:-}" ]; then
  [ "$archive_sha" = "$M1N1_SHA256" ] || die "m1n1 archive checksum mismatch: got $archive_sha"
  ok "m1n1 archive matches pinned sha256"
else
  warn "M1N1_SHA256 is not pinned; recorded $archive_sha in cache/m1n1/m1n1.sha256"
fi

rm -rf "$dest/extract"
mkdir -p "$dest/extract"
unzip -q -o "$zip" -d "$dest/extract"

macho="$(find "$dest/extract" -type f -name 'm1n1-idevice.macho' | head -n1)"
stub="$(find "$dest/extract" -type f -name 'monitor-stub.macho' | head -n1)"
[ -n "$macho" ] || die "m1n1-idevice.macho not found in $zip"
[ -n "$stub" ] || die "monitor-stub.macho not found in $zip"

install -m 0644 "$macho" "$dest/m1n1-idevice.macho"
install -m 0644 "$stub" "$dest/monitor-stub.macho"

ok "m1n1 ready: ${dest#"$ROOT"/}/{m1n1-idevice.macho,monitor-stub.macho}"
warn "nightly.link artifacts move; pin M1N1_SHA256 for reproducible builds"
