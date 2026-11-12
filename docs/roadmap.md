# Roadmap

Milestones are ordered by dependency, not by excitement. Each one has a concrete
acceptance test so "it boots" is not the only signal.

## M0 — Host + boot chain (current)

- [x] Vendor HoolockLinux kernel/m1n1/docs, `remote_boot`, Sandcastle
- [x] Apply the `d101ap` patch to `remote_boot`
- [x] Build scripts for kernel and m1n1 payload
- [ ] Kernel builds with `config_16k` + `config/android.fragment`
- [ ] Phone boots Hoolock Linux with display output
- [ ] Host reaches `172.16.42.1` over `usb0`

**Acceptance:** `scripts/boot.sh` produces a running Linux with a reachable
network gadget; no Android yet.

## M1 — Android first-stage init over NBD

- [ ] Build a minimal first-stage ramdisk (init + nbd-client + busybox/static)
- [ ] ueventd rules for `nbd0pN` and `by-name` symlinks
- [ ] fstab pointing at NBD partitions
- [ ] Serve `out/disk.img` and reach Android's first-stage logs

**Acceptance:** first-stage init detects `system`/`vendor`/`userdata`, mounts
them, and hands off to `system/bin/init` without an early panic.

## M2 — System server / SurfaceFlinger

- [ ] Build vbmeta with verity/verification disabled
- [ ] Software composer + allocator HAL
- [ ] SELinux permissive, `androidboot.verifiedbootstate=orange`
- [ ] SurfaceFlinger starts and draws the boot animation

**Acceptance:** `adb` (over usb0 or the gadget serial) shows `sys.boot_completed`
or at least a running `system_server`; display shows Android UI.

## M3 — Vendor image

- [ ] Init scripts and SELinux policy for vendor services
- [ ] `hx-touchd` packaged and started; touch events reach InputReader
- [ ] Lights/health/power stubs
- [ ] Audio stub or simple card
- [ ] `vendor.img` reproducible via `scripts/build-vendor.sh`
- [ ] 16 KiB alignment check for every vendor ELF

**Acceptance:** touch works in the UI; `vendor.img` is rebuilt from a clean tree.

## M4 — Hardware polish

- [ ] Brightness control via Hoolock's backlight driver
- [ ] Buttons mapped (power/volume; fake home button is TBA upstream)
- [ ] Wi-Fi/BT investigation (chipset support unknown)
- [ ] Sensors/camera investigation
- [ ] Enforcing SELinux
- [ ] Performance work for software rendering

**Acceptance:** day-to-day usable for a narrow set of tasks; documented gaps.

## Known blockers / risks

| Risk | Impact | Mitigation |
|---|---|---|
| 16 KiB GSI compatibility | system cannot exec | `check-gsi-16k.sh`; build AOSP system image if needed |
| No GPU driver | slow UI | software rendering; wait for upstream |
| No touch driver in kernel | no input | `hx-touchd` over I2C → uinput |
| USB gadget + NBD stability | I/O stalls | persistent NBD, retries, keep images on host |
| No TEE | software keys only | accept; document |
| checkm8 reliability | boot attempts fail | retry DFU/prep; direct cable, no hub |
| Nightly m1n1 moves | non-reproducible | record SHA-256; pin `M1N1_SHA256` |
| A10 storage unsupported | netboot required | ADR-3; NFS fallback for debug |
