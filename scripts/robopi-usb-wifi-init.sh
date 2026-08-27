#!/bin/sh
# Install-time and boot-time preparation; never changes NetworkManager profiles.
set -eu
target=6.1.99-rt36-rockchip-rk3588
if [ "$(uname -r)" != "$target" ]; then
    echo "robopi-usb-wifi: modules require $target; skipping current kernel $(uname -r)" >&2
    exit 0
fi
modprobe aic_load_fw
modprobe aic8800_fdrv
udevadm control --reload-rules
# Handle an adapter already plugged in before package installation. Future
# hotplug events use aic.rules. Never issue a global udev trigger.
for disk in /sys/class/block/*; do
    [ -e "$disk" ] || continue
    [ ! -e "$disk/partition" ] || continue
    props=$(udevadm info --query=property --path="$disk") || continue
    printf '%s\n' "$props" | grep -qx 'ID_VENDOR_ID=a69c' || continue
    printf '%s\n' "$props" | grep -Eq '^ID_MODEL_ID=(5721|5722|572a)$' || continue
    eject "/dev/${disk##*/}" || echo "robopi-usb-wifi: eject returned an error for ${disk##*/}; check lsusb for re-enumeration" >&2
done
echo "robopi-usb-wifi: preparation complete; check iw dev for the wireless interface"
