#!/bin/sh
# Capture the USB ACM console (/dev/ttyACM*) across USB re-enumeration.
#
# The Hoolock initramfs exposes the kernel console and a root shell on the
# gadget serial. If the phone panics or resets, the device node disappears and
# comes back, so a plain `cat /dev/ttyACM0` loses everything. Run this as root
# (it chmods the node) before DFU-booting the phone:
#
#   sudo nohup scripts/netboot/capture-acm.sh /tmp/idroid-acm.log >/dev/null 2>&1 &
#
# Then read /tmp/idroid-acm.log. Stop it with: sudo pkill -f capture-acm.sh
set -u

log="${1:-/tmp/idroid-acm.log}"
: > "$log"

while :; do
  seen=0
  for dev in /dev/ttyACM*; do
    [ -e "$dev" ] || continue
    seen=1
    chmod 666 "$dev" 2>/dev/null || true
    printf '\n===== %s opened %s =====\n' "$(date -Is 2>/dev/null || date)" "$dev" >> "$log"
    cat "$dev" >> "$log" 2>/dev/null
    printf '\n===== %s closed %s =====\n' "$(date -Is 2>/dev/null || date)" "$dev" >> "$log"
    sleep 0.2
  done
  [ "$seen" = 1 ] || sleep 0.2
done
