#!/bin/sh
# Install-time and boot-time preparation; drivers are provided by the BSP.
set -eu
udevadm control --reload-rules
# Handle an adapter already plugged in before package installation. Future
# Never issue a global udev trigger.
for disk in /sys/class/block/*; do
    [ -e "$disk" ] || continue
    [ ! -e "$disk/partition" ] || continue
    props=$(udevadm info --query=property --path="$disk") || continue
    printf '%s\n' "$props" | grep -qx 'ID_VENDOR_ID=a69c' || continue
    printf '%s\n' "$props" | grep -Eq '^ID_MODEL_ID=(5721|5722|572a)$' || continue
    eject "/dev/${disk##*/}" || echo "robopi-usb-wifi: eject returned an error for ${disk##*/}; check lsusb for re-enumeration" >&2
done
echo "robopi-usb-wifi: preparation complete; check iw dev for the wireless interface"
