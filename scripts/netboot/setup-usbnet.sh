#!/usr/bin/env bash
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
ok "$iface = $host_addr/24"

if command -v dnsmasq >/dev/null 2>&1; then
  pid="/tmp/idroid-dnsmasq.$iface.pid"
  if [ -f "$pid" ] && kill -0 "$(cat "$pid")" 2>/dev/null; then
    ok "dnsmasq already running (pid $(cat "$pid"))"
  else
    dnsmasq \
      --interface="$iface" \
      --bind-interfaces \
      --dhcp-range="$device_addr,$device_addr,255.255.255.0,12h" \
      --dhcp-option=3 \
      --dhcp-option=6 \
      --dhcp-authoritative \
      --pid-file="$pid" \
      --log-dhcp
    ok "dnsmasq serving DHCP $device_addr on $iface"
  fi
else
  warn "dnsmasq missing: configure Android's usb0 address statically or install it"
fi
