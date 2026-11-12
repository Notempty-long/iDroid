#!/usr/bin/env bash
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

require_cmd make
require_cmd clang
require_cmd ld.lld

kernel="$VENDOR/linux"
[ -d "$kernel" ] || die "vendor/linux missing (run scripts/vendor-sync.sh)"
require_file "$kernel/Makefile"
require_file "$kernel/scripts/kconfig/merge_config.sh"

config_src="${KERNEL_CONFIG:-$VENDOR/docs/config_16k}"
require_file "$config_src" "Hoolock config_16k"
require_file "$ROOT/config/android.fragment"

dtb="${DEVICE_DTB:-t8010-d101.dtb}"
jobs="${JOBS:-$(nproc)}"

log "config: $(basename "$config_src") + config/android.fragment"
cp "$config_src" "$kernel/.config"
(
  cd "$kernel"
  scripts/kconfig/merge_config.sh -m .config "$ROOT/config/android.fragment"
)

log "resolving config"
make -C "$kernel" ARCH=arm64 LLVM=1 olddefconfig

log "building Image.gz + dtbs with $jobs jobs"
make -C "$kernel" ARCH=arm64 LLVM=1 -j"$jobs" Image.gz dtbs

require_file "$kernel/arch/arm64/boot/Image.gz"
require_file "$kernel/arch/arm64/boot/dts/apple/$dtb" "device tree for d101ap"

mkdir -p "$OUT/kernel"
install -m 0644 "$kernel/arch/arm64/boot/Image.gz" "$OUT/kernel/Image.gz"
install -m 0644 "$kernel/arch/arm64/boot/dts/apple/$dtb" "$OUT/kernel/$dtb"
install -m 0644 "$kernel/.config" "$OUT/kernel/config"
git -C "$kernel" rev-parse HEAD > "$OUT/kernel/kernel.commit"

ok "kernel: ${OUT#"$ROOT"/}/kernel/Image.gz"
ok "dtb:    ${OUT#"$ROOT"/}/kernel/$dtb"
