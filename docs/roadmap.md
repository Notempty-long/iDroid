# Roadmap

Milestones are ordered by dependency, not by excitement. Each one has a concrete
acceptance test so "it boots" is not the only signal.

## M0 — Boot chain (done)

- [x] Vendor HoolockLinux kernel/m1n1/docs, `remote_boot`, Sandcastle
- [x] Apply the `d101ap` patch to `remote_boot`
- [x] Kernel builds with `config_16k` (16 KiB pages)
- [x] Phone boots Hoolock Linux; gadget enumerates; ACM console captured
- [x] Host reaches the phone over `usb0`

**Acceptance:** `make boot` produces a running Linux with a reachable USB
network gadget.

## M1 — Linux rootfs over NBD (current)

- [x] Static `nbd-client` in the first-stage ramdisk
- [x] NBD link verified from the phone (`NBDMAGIC`, GPT visible)
- [x] Alpine rootfs image + GPT disk builder
- [x] `linux.sh`: connect, mount `nbd0p1`, `switch_root`
- [ ] First successful Alpine boot and console login
- [ ] Survive a gadget re-enumeration without losing the rootfs

**Acceptance:** prompt on `ttyGS0` from Alpine, `poweroff` cleanly stops the
phone, and a second boot works without touching the host image.

## M2 — Input: touchscreen

Hoolock has the `apple,z2` driver, but the T8010 device tree has no SPI
controller or touch node, and the iPhone 7 panel is not a Touch Bar panel.
Port the register/GPIO/rail data from Corellium's `linux-sandcastle`
(`hx,spi`, `hx,touch`, `D10.mtprops`) into the Hoolock tree, then feed events
through evdev/uinput.

**Acceptance:** `evtest` reports multitouch coordinates.

## M3 — Bluetooth

Add the BCM combo UART/serdev node (Corellium uses `uart1` with
`brcm,bcm4345c5`) and the GPIO/PMU wiring; enable `hci_bcm` and provide the
firmware patch/NVRAM from iOS.

**Acceptance:** `hciconfig`/`bluetoothctl` sees the controller and can scan.

## M4 — WiFi

Add a T8010 PCIe host node (plus DART/SART/MSI plumbing) and a
`brcmfmac` child with `brcm,board-type`, calibration blob and NVRAM.

**Acceptance:** `iw dev` lists an interface and it associates.

## M5 — Internal storage (optional)

Port the ANS2 NVMe node and mailbox/SART wiring for T8010 (only A11 and M1 are
supported today). Until then NBD remains the rootfs transport.

**Acceptance:** `nvme list` shows the internal disk; rootfs can live on it.

## Known blockers / risks

| Risk | Impact | Mitigation |
|---|---|---|
| No T8010 SPI/PCIe/UART-BT DT nodes | no touch/WiFi/BT | port data from `linux-sandcastle` |
| No GPU/display controller driver | slow UI | software rendering; simple framebuffer |
| USB gadget + NBD stability | I/O stalls | persistent NBD, retries, keep images on host |
| No TEE | software keys only | accept; document |
| checkm8 reliability | boot attempts fail | retry DFU/prep; direct cable, no hub |
| Nightly m1n1 moves | non-reproducible | record SHA-256; pin `M1N1_SHA256` |
| A10 storage unsupported | netboot required | M5; NFS fallback for debug |
