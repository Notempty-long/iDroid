#!/usr/bin/env bash
# Configure the host side of the USB Ethernet link.
#
# The phone's first-stage initramfs assigns 172.16.42.1 to its gadget and runs
# unudhcpd, handing 172.16.42.2 to the host. We therefore use a static address
# here instead of running a second DHCP server.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib.sh"

iface="${1:-usb0}"
host_addr="172.16.42.2"
device_addr="172.16.42.1"
host_net="172.16.42.0/24"

require_root "scripts/netboot/setup-usbnet.sh"
require_cmd ip

if ! ip link show "$iface" >/dev/null 2>&1; then
  die "interface $iface not found (see dmesg; USB NICs may be named enx...)"
fi

ip addr replace "$host_addr/24" dev "$iface"
ip link set "$iface" up
ok "$iface = $host_addr/24 (phone is the DHCP server at $device_addr)"

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
