#!/usr/bin/env bash
# Build a static aarch64 nbd-client for the Android first-stage ramdisk.
#
# The kernel has CONFIG_BLK_DEV_NBD=y, but userspace still needs the ioctl
# handshake. A static binary keeps the ramdisk free of a second libc.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

version="${NBD_VERSION:-3.27.1}"
url="https://github.com/NetworkBlockDevice/nbd/releases/download/nbd-${version}/nbd-${version}.tar.xz"
sha256="${NBD_SHA256:-ef1fe160ac3ff602ae4029d413b0d530036e352a1e6a427402776c1a7aaf3716}"
cross="${CROSS_COMPILE:-aarch64-linux-gnu-}"

require_cmd curl
require_cmd tar
require_cmd sha256sum
require_cmd make
require_cmd "${cross}gcc"

dest="$CACHE/nbd-client/$version"
src="$dest/nbd-${version}"
tarball="$dest/nbd-${version}.tar.xz"

mkdir -p "$dest"
if [ ! -f "$tarball" ]; then
  log "downloading nbd $version"
  curl -fL --retry 3 --retry-delay 2 -o "$tarball.tmp" "$url"
  mv "$tarball.tmp" "$tarball"
fi

printf '%s  %s\n' "$sha256" "$tarball" | sha256sum -c - || die "nbd tarball checksum mismatch"

if [ ! -x "$dest/nbd-client" ]; then
  rm -rf "$src"
  tar -C "$dest" -xf "$tarball"
  log "cross-compiling nbd-client for aarch64 (static)"
  (
    cd "$src"
    ./configure --host="${cross%-}" --without-gnutls --without-libnl \
      CFLAGS="-O2" >/dev/null
    make -j"${JOBS:-$(nproc)}" nbd-client LDFLAGS="-all-static" >/dev/null
  )
  "${cross}strip" -o "$dest/nbd-client" "$src/nbd-client"
fi

require_file "$dest/nbd-client"
if "${cross}readelf" -l "$dest/nbd-client" 2>/dev/null | grep -q 'INTERP'; then
  die "nbd-client is dynamically linked; expected a static binary"
fi

ok "nbd-client: ${dest#"$ROOT"/}/nbd-client ($(stat -c%s "$dest/nbd-client") bytes, static aarch64)"
