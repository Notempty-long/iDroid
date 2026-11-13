#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib.sh"

require_file "$ROOT/config/netboot.conf" "repository is incomplete"
# shellcheck disable=SC1091
. "$ROOT/config/netboot.conf"

img="${1:-$OUT/disk-linux.img}"
port="${2:-$NB_NBD_PORT}"
bind="${NBD_BIND:-$NB_HOST_IP}"
export_name="${NBD_EXPORT:-$NB_NBD_EXPORT}"

require_cmd qemu-nbd
require_file "$img" "run scripts/netboot/make-linux-disk.sh (or pass an image)"

if ! ip addr show 2>/dev/null | grep -qF "inet $bind/"; then
  warn "$bind is not configured on any interface; run setup-usbnet.sh first"
fi

confirm "Serve ${img#"$ROOT"/} read-write over NBD on $bind:$port?"
log "NBD: $img -> $bind:$port (export '$export_name', persistent, shared)"
exec qemu-nbd --format=raw --persistent --shared=4 --export-name="$export_name" \
  --bind="$bind" --port="$port" "$img"
