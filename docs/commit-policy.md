# Commit policy

The project is large and mostly vendored. Keep history reviewable:

- One logical change per commit; subject `scope: summary`
  (`kernel: enable binderfs`, `netboot: add NBD server wrapper`).
- Commit docs, build logic, and vendor-pin changes separately.
- Never commit build outputs (`out/`), downloads (`cache/`), disk/GSI images, or
  the nightly m1n1 archive.
- Never commit changes inside a submodule worktree. Put them in
  `patches/<submodule>/NNNN-summary.patch` and apply with
  `scripts/apply-patches.sh`.
- When bumping a vendor pin, include the regenerated `vendor/versions.lock` in
  the same commit and say why in the body.
- Patches must apply cleanly on the pinned commit; if upstream moved, rebase the
  patch rather than hand-editing the vendor tree.
- Large behavioural changes (kernel config, netboot mechanism, GSI version) also
  update `docs/decisions.md`.

This follows the user's rule: every significant change gets its own commit.
