#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail
state=/etc/roboparty/wifi-interface
nmconf=/etc/NetworkManager/conf.d/90-robopi-wifi-select.conf
die() { echo "robopi-wifi-select: $*" >&2; exit 1; }
wireless() { [[ -d /sys/class/net/$1/wireless ]]; }
is_usb() { [[ $(readlink -f "/sys/class/net/$1/device") == */usb*/* ]]; }
case "${1:-status}" in
    status)
        if [[ -f $state ]]; then cat "$state"; else echo 'Selection: default (/etc/default/wifi-reset)'; fi
        nmcli device status
        exit 0 ;;
    usb|onboard) mode=$1 ;;
    *) die 'Usage: robopi-wifi-select {usb [INTERFACE]|onboard [INTERFACE]|status}' ;;
esac
[[ $EUID == 0 ]] || die 'Run with sudo (use wired SSH or serial console).'
command -v nmcli >/dev/null || die 'NetworkManager is required.'
iface=${2:-}
if [[ -z $iface ]]; then
    candidates=()
    for path in /sys/class/net/*; do
        name=${path##*/}
        wireless "$name" || continue
        if [[ $mode == usb ]]; then
            is_usb "$name" && candidates+=("$name")
        else
            is_usb "$name" || candidates+=("$name")
        fi
    done
    [[ ${#candidates[@]} == 1 ]] || die "Found ${#candidates[@]} matching interfaces; specify one explicitly."
    iface=${candidates[0]}
fi
[[ $iface =~ ^[a-zA-Z0-9_.-]+$ ]] || die 'Invalid interface name.'
wireless "$iface" || die "Wireless interface not found: $iface"
if [[ $mode == usb ]]; then
    is_usb "$iface" || die "$iface is not USB Wi-Fi."
else
    ! is_usb "$iface" || die "$iface is USB, not onboard Wi-Fi."
fi
echo "Selecting $iface. Other Wi-Fi interfaces will be disabled; wireless SSH may disconnect."
install -d /etc/roboparty /etc/NetworkManager/conf.d
tmp=$(mktemp /etc/NetworkManager/conf.d/.robopi-wifi.XXXXXX)
trap 'rm -f "$tmp"' EXIT
printf '[device-robopi-wifi-select]\nmatch-device=type:wifi;except:interface-name:%s\nmanaged=0\n' "$iface" > "$tmp"
chmod 644 "$tmp"
mv "$tmp" "$nmconf"
printf 'WIFI_INTERFACE=%s\n' "$iface" > "$state"
chmod 644 "$state"
systemctl stop wifi-reset.service
nmcli general reload
for path in /sys/class/net/*; do
    name=${path##*/}
    wireless "$name" || continue
    [[ $name == "$iface" ]] && continue
    nmcli device set "$name" managed no
    ip link set dev "$name" down
done
nmcli device set "$iface" managed yes
systemctl restart wifi-reset.service
echo "Saved: $iface. Driver/firmware must already be installed."
echo "Connect: sudo nmcli --ask device wifi connect SSID ifname $iface"
echo 'Existing active AP/client connections on the selected interface are preserved.'
