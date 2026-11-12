#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

require_root "scripts/boot.sh"
require_cmd irecovery
require_cmd ipsw
require_cmd lsusb

blob="$OUT/boot/m1n1-linux.macho"
stub="$OUT/boot/monitor-stub.macho"
boot_tool="$VENDOR/remote_boot/remoteboot.sh"

require_file "$blob" "run scripts/build-m1n1-blob.sh"
require_file "$stub" "run scripts/fetch-m1n1.sh"
[ -x "$boot_tool" ] || die "vendor/remote_boot/remoteboot.sh missing (run scripts/vendor-sync.sh)"

if ! lsusb 2>/dev/null | grep -qF '05ac:1227'; then
  die "no DFU device (05ac:1227); put the iPhone 7 in DFU first"
fi

confirm "Boot iPhone9,3 with $blob (device must stay connected)?"
exec "$boot_tool" boot "$blob" "$stub"
