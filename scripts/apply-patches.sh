#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

require_cmd git

shopt -s nullglob
patches=("$ROOT"/patches/*/*.patch)
if [ "${#patches[@]}" -eq 0 ]; then
  warn "no patches found under patches/"
  exit 0
fi

for patch in "${patches[@]}"; do
  name="$(basename "$(dirname "$patch")")"
  target="$VENDOR/$name"
  rel="${patch#"$ROOT"/}"

  [ -d "$target" ] || die "patch target missing: $target (run scripts/vendor-sync.sh)"

  if git -C "$target" apply --reverse --check "$patch" >/dev/null 2>&1; then
    ok "already applied: $rel"
    continue
  fi

  if ! git -C "$target" apply --check "$patch"; then
    die "patch does not apply: $rel (rebase it against the pinned commit)"
  fi

  git -C "$target" apply "$patch"
  ok "applied: $rel"
done
