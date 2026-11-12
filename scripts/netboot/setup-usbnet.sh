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

require_root "scripts/netboot/setup-usbnet.sh"
require_cmd ip

if ! ip link show "$iface" >/dev/null 2>&1; then
  die "interface $iface not found (see dmesg; USB NICs may be named enx...)"
fi

ip addr replace "$host_addr/24" dev "$iface"
ip link set "$iface" up
ok "$iface = $host_addr/24 (phone is the DHCP server at $device_addr)"

# The phone runs unudhcpd; verify the link is actually up before NBD.
if [ "$(cat "/sys/class/net/$iface/carrier" 2>/dev/null || echo 0)" != "1" ]; then
  warn "no carrier on $iface yet: boot the phone into the first-stage initramfs"
fi
