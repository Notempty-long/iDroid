#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

require_cmd curl
require_cmd unzip
require_cmd sha256sum

if [ "$#" -ge 1 ]; then
  url="$1"
  sha="${2:-}"
  name="${3:-$(basename "$url" .zip)}"
else
  env_file="$ROOT/config/gsi.env"
  require_file "$env_file"
  # shellcheck disable=SC1090
  . "$env_file"
  url="${GSI_URL:?GSI_URL missing from config/gsi.env}"
  sha="${GSI_SHA256:-}"
  name="${GSI_NAME:-$(basename "$url" .zip)}"
fi

[ -n "$url" ] || die "no GSI URL"
archive="$CACHE/downloads/$(basename "$url")"
dest="$CACHE/gsi/$name"

mkdir -p "$CACHE/downloads" "$CACHE/gsi"
if [ ! -f "$archive" ]; then
  log "downloading GSI: $url"
  curl -fL --retry 3 --retry-delay 2 -o "$archive.tmp" "$url"
  mv "$archive.tmp" "$archive"
fi

if [ -n "$sha" ]; then
  printf '%s  %s\n' "$sha" "$archive" | sha256sum -c - || die "GSI checksum mismatch"
  ok "GSI checksum verified"
else
  warn "no SHA-256 supplied; computed $(sha256sum "$archive" | awk '{print $1}')"
fi

if [ ! -f "$dest/system.img" ]; then
  log "extracting $(basename "$archive")"
  rm -rf "$dest"
  mkdir -p "$dest"
  unzip -q -o "$archive" -d "$dest"
fi

require_file "$dest/system.img" "GSI zip did not contain system.img"

ln -sfn "$name" "$CACHE/gsi/current"
ok "GSI ready: ${dest#"$ROOT"/}/system.img"
warn "Google's GSI license: development/app-validation use only; do not redistribute"
warn "verify 16 KiB compatibility with scripts/check-gsi-16k.sh"
