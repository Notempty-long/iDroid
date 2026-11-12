# Vendored sources

These are git submodules, pinned by the gitlinks in the parent repository.
`vendor/versions.lock` records the URL, branch, and commit for each tree.

| Path | Upstream | Branch | Why |
|---|---|---|---|
| `linux` | HoolockLinux/linux | `hoolock` | A10 kernel, 16 KiB pages, display/USB support |
| `m1n1` | HoolockLinux/m1n1 | `idevice` | loader payload and monitor stub |
| `remote_boot` | HoolockLinux/remote_boot | `master` | iBoot-method boot chain (patched) |
| `projectsandcastle` | corellium/projectsandcastle | `master` | `hx-touchd`, `loader`, `syscfg`, Android reference |
| `docs` | HoolockLinux/docs | `master` | `config_16k`, boot documentation, feature tables |

## Sync

```sh
scripts/vendor-sync.sh
```

This runs `git submodule update --init --recursive --depth 1`, applies the
patches in `patches/`, and regenerates `vendor/versions.lock`.

The Linux tree is shallow (~300 MB of git objects). If a later clone cannot
fetch the pinned commit because the branch moved, run with `--remote`:

```sh
git submodule update --init --recursive --remote --depth 1
```

then update the pin intentionally and commit the new gitlink.

## Nested submodules

`remote_boot` has its own submodules (`gaster`, `hBootPatcher`,
`hKernelFWExtractor`). `--recursive` initialises them. Its own
`remoteboot.sh` also runs `git submodule update --init --recursive` on demand.

## Do not edit in place

Changes belong in `patches/<name>/`; the vendored worktrees are allowed to be
dirty after patching but their gitlinks must not move unless you are deliberately
bumping the pin.
