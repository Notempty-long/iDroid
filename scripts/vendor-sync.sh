#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

cd "$ROOT"

log "initialising vendored sources (shallow)"
git submodule sync --recursive
# remote_boot's nested submodules use git@github.com URLs; rewrite them to
# HTTPS so initialisation works without GitHub SSH keys. The environment form
# propagates the setting into the nested git invocations.
submodule_git() {
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0='url.https://github.com/.insteadOf' \
  GIT_CONFIG_VALUE_0='git@github.com:' \
    git submodule update --init --recursive "$@"
}

if ! submodule_git --depth 1; then
  warn "shallow submodule update failed; retrying with full history"
  submodule_git
fi

"$ROOT/scripts/apply-patches.sh"
"$ROOT/scripts/versions-lock.sh"

ok "vendored sources ready (patches applied, lock regenerated)"
