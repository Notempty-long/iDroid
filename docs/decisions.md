# Decisions

Short ADR-style log. Each entry records the choice and why; revisit only with a
concrete reason.

## ADR-1: iBoot + `remote_boot`, not pongoOS

**Decision:** boot via checkm8 → patched iBSS → m1n1 `idevice` → Linux.

**Why:** the project already uses Hoolock's prebuilt `m1n1-idevice` and
`remote_boot`; this path does not depend on internal storage or on a working iOS
installation. `remote_boot` prepares everything once per model.

**Consequence:** the boot tool is patched to hard-code `0x8010`/`d101ap`/
`iPhone9,3`; it is not model-generic. `0x8010` is single-stage (iBSS only).

## ADR-2: 16 KiB pages

**Decision:** kernel and Android userspace use 16 KiB pages.

**Why:** Hoolock's A10 `config_16k` is 16 KiB; Android 16 requires 16 KiB support
on new 64-bit devices. Mixing 4 KiB userspace with a 16 KiB kernel fails at ELF
load time.

**Consequence:** the GSI must be 16 KiB-compatible (`scripts/check-gsi-16k.sh`);
our vendor ELFs must be linked with 16 KiB max-page-size.

## ADR-3: netboot via NBD over the USB Ethernet gadget

**Decision:** serve one GPT disk image from the host over NBD; no Android data on
the phone.

**Why:** HoolockLinux documents internal storage support only for A11; A10 has
no usable block driver in this port. USB device mode works, and Android needs
block devices (not just files) for `system`/`vendor`/`userdata`/`vbmeta`.

**Consequence:** host must run DHCP + `qemu-nbd`; first boot is network-bound;
`userdata` durability is the host's responsibility. NFS root remains a debug
fallback only.

## ADR-4: Android 16 GSI, no VNDK

**Decision:** Android 16 QPR2 ARM64 GSI as `system`; vendor built alongside it;
no VNDK snapshot.

**Why:** VNDK is deprecated in Android 15 and vendor snapshot was removed with
it. Vendor libraries belong in `vendor` and link against LLNDK. Picking the
newest stable release avoids maintaining a legacy VNDK.

**Consequence:** an older GSI (≤ Android 14) would require matching VNDK 34/35
libraries built from AOSP; not planned.

## ADR-5: vendoring via shallow submodules + tracked patches

**Decision:** upstream trees are git submodules under `vendor/`, shallow where
large; local changes are patches in `patches/<submodule>/`.

**Why:** the kernel is too large to vendor as files; gitlinks pin exact commits
and patches keep local changes reviewable and rebasable.

**Consequence:** `scripts/vendor-sync.sh` must run after clone or branch update;
submodule worktrees become intentionally dirty after patching. Do not commit
submodule worktree changes; change the patch instead.

## ADR-6: no TEE

**Decision:** no use of the Secure Enclave; Keymaster/Gatekeeper will be software
implementations.

**Why:** HoolockLinux has no TEE driver, and the boot chain deliberately bypasses
Apple's secure boot. There is no trustworthy path to the SEP for Android.

**Consequence:** no hardware-backed keys, no StrongBox, no Widevine L1, no
hardware attestation. Some CTS tests will fail permanently.

## ADR-7: software rendering first

**Decision:** bring up display with software composition; no GPU driver work in
the first milestones.

**Why:** A10 GPU support is TBA upstream. A visible Android UI is still possible
with software composition and is a better early milestone than blocked GPU work.

**Consequence:** slow UI, no games, high CPU usage. Revisit when Hoolock/Asahi
exposes a usable GPU path.
