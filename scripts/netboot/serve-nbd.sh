#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib.sh"

img="${1:-$OUT/disk.img}"
port="${2:-10809}"
bind="${NBD_BIND:-172.16.42.2}"

require_cmd qemu-nbd
require_file "$img" "run scripts/netboot/make-disk.sh"

if ! ip addr show 2>/dev/null | grep -qF "inet $bind/"; then
  warn "$bind is not configured on any interface; run setup-usbnet.sh first"
fi

confirm "Serve ${img#"$ROOT"/} read-write over NBD on $bind:$port?"
log "NBD: $img -> $bind:$port (persistent, shared)"
exec qemu-nbd --format=raw --persistent --shared=4 --bind="$bind" --port="$port" "$img"
