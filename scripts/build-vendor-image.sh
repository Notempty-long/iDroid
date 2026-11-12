#!/usr/bin/env bash
# Build the vendor partition image.
#
# The GSI archive is system-only, but Treble init loads a split SELinux policy:
# it requires /vendor/etc/selinux/{vendor_sepolicy.cil,plat_pub_versioned.cil}
# and plat_sepolicy_vers.txt, and compiles them with /system/bin/secilc. This
# image supplies those files plus a vendor build.prop and init hook file.
#
# We mount this partition read-only at /vendor. Nothing here needs a vendor
# domain yet, so vendor_sepolicy.cil is intentionally empty.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

require_cmd mke2fs
require_cmd truncate

out="${VENDOR_IMG:-$OUT/vendor.img}"
size="${VENDOR_SIZE:-1G}"
version="${SELINUX_MAPPING_VERSION:-202504}"
system="${SYSTEM_IMG:-$CACHE/gsi/current/system.img}"
root="$OUT/vendor/root"

# The mapping file must exist in the platform image, otherwise init's secilc
# invocation fails. Validate when the GSI has been extracted.
if [ -f "$system" ]; then
  require_cmd debugfs
  if ! debugfs -R "stat /system/etc/selinux/mapping/$version.cil" "$system" >/dev/null 2>&1; then
    die "GSI has no mapping/$version.cil; set SELINUX_MAPPING_VERSION to one of the available files"
  fi
else
  warn "GSI not extracted; cannot validate SELinux mapping version $version"
fi

rm -rf "$root"
mkdir -p "$root"
cp -a "$ROOT/config/vendor-image/." "$root/"

printf '%s\n' "$version" > "$root/etc/selinux/plat_sepolicy_vers.txt"

# Optional context files: create them empty so tools do not warn about a
# missing vendor side of the split policy.
for f in \
  vendor_file_contexts \
  vendor_property_contexts \
  vendor_hwservice_contexts \
  vendor_service_contexts \
  vendor_seapp_contexts \
  vendor_keystore2_key_contexts \
  vendor_tee_service_contexts; do
  : > "$root/etc/selinux/$f"
done

mkdir -p "$(dirname "$out")"
truncate -s "$size" "$out.tmp"
log "building $size ext4 vendor image (mapping $version)"
mke2fs -q -F -t ext4 -b 4096 -m 0 -L vendor -d "$root" "$out.tmp"
mv "$out.tmp" "$out"

ok "vendor image: ${out#"$ROOT"/} ($(stat -c%s "$out") bytes)"
