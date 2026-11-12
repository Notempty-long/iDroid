#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

cd "$ROOT"

log "initialising vendored sources (shallow)"
git submodule sync --recursive
if ! git submodule update --init --recursive --depth 1; then
  warn "shallow submodule update failed; retrying with full history"
  git submodule update --init --recursive
fi

"$ROOT/scripts/apply-patches.sh"
"$ROOT/scripts/versions-lock.sh"

ok "vendored sources ready (patches applied, lock regenerated)"
