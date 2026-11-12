# Patches

Local changes to vendored trees live here, one directory per submodule:

```
patches/<submodule-name>/NNNN-summary.patch
```

`scripts/apply-patches.sh` applies them in lexical order to
`vendor/<submodule-name>/` with `git apply`. A patch that is already applied is
detected with `git apply --reverse --check` and skipped, so the script is
idempotent.

Rules:

- Patches must apply cleanly to the pinned upstream commit.
- Do not hand-edit the vendor worktree as the source of truth; if you must
  iterate there, export the final diff back into the patch and reset the
  submodule (`git -C vendor/<name> checkout -- .`).
- After `scripts/vendor-sync.sh`, patches are re-applied automatically.
- Vendored trees will show as "modified content" in `git status`; that is
  expected and must not be committed.

## Current patches

| Patch | Target | Why |
|---|---|---|
| `remote_boot/0001-hardcode-iphone9-3-device-info.patch` | `vendor/remote_boot` | `irecovery -q` is unreliable after pwn on this setup; hard-code `CPID=0x8010`, `MODEL=d101ap`, `PRODUCT=iPhone9,3` for the iPhone 7. |
