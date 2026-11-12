#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

fails=0

check() {
  local cmd="$1" note="${2:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  ok    %-18s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '  MISS  %-18s %s\n' "$cmd" "$note"
    fails=$((fails + 1))
  fi
}

optional() {
  local cmd="$1" note="${2:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  ok    %-18s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '  warn  %-18s %s\n' "$cmd" "$note"
  fi
}

echo "== build =="
check git
check make
check clang
check ld.lld
check bc
check flex
check bison
check curl
check unzip
check sha256sum
check xxd

echo "== boot chain =="
check irecovery "libimobiledevice"
check ipsw "blacktop/ipsw >= 3.1.719"
check lsusb "util-linux"
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libusb-1.0 2>/dev/null; then
  printf '  ok    %-18s %s\n' "libusb-1.0" "headers for gaster"
else
  printf '  warn  %-18s %s\n' "libusb-1.0" "headers needed to build gaster"
fi

echo "== netboot =="
check qemu-nbd
check dnsmasq
check ip

echo "== disk images =="
check sgdisk
check mkfs.ext4
check e2fsck

echo "== optional =="
optional dtc "kernel builds its own if missing"
optional debugfs "GSI 16K check"
optional readelf "GSI 16K check"
optional aarch64-linux-gnu-gcc "native builds may use clang/LLVM instead"
optional adb "not used until Android boots"
optional shellcheck "script linting"

if command -v ipsw >/dev/null 2>&1; then
  version="$(ipsw --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
  if [ -n "$version" ]; then
    if [ "$(printf '%s\n%s\n' "3.1.719" "$version" | sort -V | head -n1)" = "3.1.719" ]; then
      printf '  ok    %-18s %s\n' "ipsw version" "$version"
    else
      printf '  warn  %-18s %s\n' "ipsw version" "$version (< 3.1.719 can generate broken LZSS IMG4)"
    fi
  fi
fi

if [ "$fails" -ne 0 ]; then
  printf '\n%d required command(s) missing\n' "$fails" >&2
  exit 1
fi
printf '\nhost looks ready\n'
