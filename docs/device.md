# Device: iPhone 7 (`iPhone9,3`)

## Identity

| Field | Value |
|---|---|
| Marketing name | iPhone 7 (GSM / Intel baseband) |
| Apple model | `iPhone9,3` |
| Board / device tree | `d101ap` → `t8010-d101.dtb` |
| SoC | Apple A10 Fusion, `t8010`, CPID `0x8010` |
| CPU | 2× Hurricane + 2× Zephyr, arm64 |
| RAM | 2 GiB |
| Display | 750×1334, 4.7", IPS |
| Storage | NVMe (not usable by this port) |
| USB | 2.0 device mode (Lightning) |
| Bootrom | checkm8-vulnerable (A10) |
| Secure enclave / TEE | present, **not used** |
| Page size | 16 KiB |

Do not confuse the variants:

| Model | Board | Baseband | Marketing |
|---|---|---|---|
| `iPhone9,1` | `d10ap` | Qualcomm | iPhone 7 |
| `iPhone9,3` | `d101ap` | Intel | iPhone 7 |
| `iPhone9,2` | `d11ap` | Qualcomm | iPhone 7 Plus |
| `iPhone9,4` | `d111ap` | Intel | iPhone 7 Plus |

This project targets `d101ap` only. The `remote_boot` patch hard-codes that
identity, so a prepared/boot bundle **will not** work on another model without
regenerating it.

## What the hardware can do under HoolockLinux (A10)

From `vendor/docs/features/A10.md`:

| Feature | Status |
|---|---|
| Device tree, main display, buttons | 6.13 |
| Brightness | 6.15 |
| USB 2.0 device mode | linux-apple |
| RTC, cpufreq | available |
| GPU | TBA (no acceleration) |
| Touch | not in the Hoolock table; Sandcastle `hx-touchd` is the userspace path |
| Internal storage | not supported on A10 |

Consequences for Android:

- Display output is available, so SurfaceFlinger can bring up a framebuffer.
- The USB gadget is the only practical data path → netboot.
- Touch needs `hx-touchd` (I2C → `/dev/uinput`), which becomes a vendor service.
- No GPU driver → software rendering (SwiftShader / software HWC).

## DFU

1. Connect the phone directly (no hub) with a data-capable Lightning cable.
2. Enter DFU: hold **Power + Volume Down** for 10 s, release Power, keep
   Volume Down for ~5 s.
3. Verify on the host:

   ```sh
   lsusb | grep 05ac:1227
   ```

`remote_boot` also expects `gaster` to be buildable (`libusb-1.0` headers).

## Notes

- `D10.mtprops` in the repository root is an Apple firmware configuration blob
  for the `d10` board. It is unrelated to `d101ap`; keep it out of commits unless
  it is deliberately added for a D10 experiment.
- Never run `scripts/boot.sh` with a different phone attached: the tooling is
  pinned to `iPhone9,3`.
