#!/usr/bin/env bash
# Configure the host side of the USB Ethernet link.
#
# The phone's first-stage initramfs assigns NB_PHONE_IP to its gadget and runs
# unudhcpd, handing NB_HOST_IP to the host. We therefore use a static address
# here instead of running a second DHCP server. Both addresses come from
# config/netboot.conf, the same file baked into the initramfs.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib.sh"

require_file "$ROOT/config/netboot.conf" "repository is incomplete"
# shellcheck disable=SC1091
. "$ROOT/config/netboot.conf"

iface="${1:-usb0}"
host_addr="$NB_HOST_IP"
device_addr="$NB_PHONE_IP"
prefix="$NB_PREFIX"

# Network address for the firewall rule (no external tools needed).
IFS=. read -r _a _b _c _d <<<"$host_addr"
_mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
_ip=$(( (_a << 24) | (_b << 16) | (_c << 8) | _d ))
_net=$(( _ip & _mask ))
host_net="$(( (_net >> 24) & 255 )).$(( (_net >> 16) & 255 )).$(( (_net >> 8) & 255 )).$(( _net & 255 ))/$prefix"

require_root "scripts/netboot/setup-usbnet.sh"
require_cmd ip

if ! ip link show "$iface" >/dev/null 2>&1; then
  die "interface $iface not found (see dmesg; USB NICs may be named enx...)"
fi

ip addr replace "$host_addr/$prefix" dev "$iface"
ip link set "$iface" up
ok "$iface = $host_addr/$prefix (phone is the DHCP server at $device_addr)"

# Host firewalls often allow ICMP but drop inbound TCP from the gadget, which
# makes nbd-client (and wget for debugging) look like it hangs with no error.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  if ufw allow from "$host_net" comment 'iDroid USB netboot' >/dev/null 2>&1; then
    ok "ufw: inbound traffic from $host_net allowed"
  else
    warn "ufw is active; run: ufw allow from $host_net"
  fi
fi

# The phone runs unudhcpd; verify the link is actually up before NBD.
if [ "$(cat "/sys/class/net/$iface/carrier" 2>/dev/null || echo 0)" != "1" ]; then
  warn "no carrier on $iface yet: boot the phone into the first-stage initramfs"
fi
