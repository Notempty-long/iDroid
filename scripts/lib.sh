#!/usr/bin/env bash
# Shared helpers. Source this file; do not execute it.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
VENDOR="$ROOT/vendor"
OUT="$ROOT/out"
CACHE="$ROOT/cache"

log()  { printf '[*] %s\n' "$*" >&2; }
ok()   { printf '[+] %s\n' "$*" >&2; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[-] %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1${2:+ ($2)}"
}

require_file() {
  [ -f "$1" ] || die "missing file: $1${2:+ ($2)}"
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "must run as root: $*"
}

# Ask before anything destructive or device-facing. YES=1 skips the prompt.
confirm() {
  local prompt="$1"
  if [ "${YES:-0}" = "1" ]; then
    return 0
  fi
  [ -t 0 ] || die "refusing non-interactive action; re-run with YES=1: $prompt"
  local answer
  read -r -p "$prompt [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) die "aborted" ;;
  esac
}
