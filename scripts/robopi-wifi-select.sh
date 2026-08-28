#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail
state=/etc/roboparty/wifi-interface
nmconf=/etc/NetworkManager/conf.d/90-robopi-wifi-select.conf
disabled=/etc/roboparty/wifi-auto-disabled
action=${1:-status}
die() { echo "robopi-wifi-select: $*" >&2; exit 1; }
wireless() { [[ -d /sys/class/net/$1/wireless ]]; }
is_usb() { [[ $(readlink -f "/sys/class/net/$1/device") == */usb*/* ]]; }
case "${1:-status}" in
    status)
        if [[ -e $disabled ]]; then echo 'USB auto selection: disabled'; else echo 'USB auto selection: enabled'; fi
        if [[ -f $state ]]; then cat "$state"; else echo 'Selection: default (/etc/default/wifi-reset)'; fi
        nmcli device status
        exit 0 ;;
    usb|onboard) mode=$1 ;;
    auto|auto-usb) mode=usb ;;
    *) die 'Usage: robopi-wifi-select {auto|usb [INTERFACE]|onboard [INTERFACE]|status}' ;;
esac
[[ $EUID == 0 ]] || die 'Run with sudo (use wired SSH or serial console).'
command -v nmcli >/dev/null || die 'NetworkManager is required.'
install -d /run/roboparty /etc/roboparty
exec 9>/run/roboparty/wifi-select.lock
flock -w 40 9 || die 'Another selection is still running.'
if [[ $action == auto-usb && -e $disabled ]]; then echo 'USB auto selection disabled by user.'; exit 0; fi
if [[ $action == auto ]]; then rm -f "$disabled"; fi
# Boot scanning must not race the udev NAME assignment. Never rename a live link.
udevadm settle --timeout=15 || die 'udev is still processing devices; retry selection.'
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
    if [[ $action == auto || $action == auto-usb ]]; then
        saved=''
        if [[ -f $state ]]; then saved=$(sed -n 's/^WIFI_INTERFACE=//p' "$state"); fi
        for name in "${candidates[@]}"; do
            if [[ $name == "$saved" ]]; then iface=$name; break; fi
        done
        if [[ -z $iface && ${#candidates[@]} == 1 ]]; then iface=${candidates[0]}; fi
        if [[ -z $iface ]]; then
            echo "Auto selection: ${#candidates[@]} USB Wi-Fi adapters; no unique choice. Keeping current configuration."
            exit 0
        fi
    else
        [[ ${#candidates[@]} == 1 ]] || die "Found ${#candidates[@]} matching interfaces; specify one explicitly."
        iface=${candidates[0]}
    fi
fi
[[ $iface =~ ^[a-zA-Z0-9_.-]+$ ]] || die 'Invalid interface name.'
wireless "$iface" || die "Wireless interface not found: $iface"
if [[ $mode == usb ]]; then
    is_usb "$iface" || die "$iface is not USB Wi-Fi."
else
    ! is_usb "$iface" || die "$iface is USB, not onboard Wi-Fi."
fi
if [[ $action == auto || $action == auto-usb ]]; then
    for path in /sys/class/net/*; do
        name=${path##*/}
        wireless "$name" || continue
        [[ $name != "$iface" ]] || continue
        if iw dev "$name" info 2>/dev/null | grep -qE '^[[:space:]]*type AP$'; then
            echo "AP active on $name; automatic switch deferred. Use explicit usb selection to override."
            exit 0
        fi
    done
fi
# udev can report the interface before NetworkManager has discovered it.
ready=no
for ((attempt=0; attempt<15; attempt++)); do
    if nmcli -g GENERAL.DEVICE device show "$iface" >/dev/null 2>&1; then ready=yes; break; fi
    wireless "$iface" || die "$iface was unplugged."
    sleep 1
done
[[ $ready == yes ]] || die "NetworkManager has not discovered $iface yet."
if [[ $mode == onboard ]]; then touch "$disabled";
elif [[ $action == usb ]]; then rm -f "$disabled"; fi
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
trap 'rm -f "$tmp"; systemctl start wifi-reset.service || true' EXIT
nmcli general reload
nmcli device set "$iface" managed yes
# Preserve saved credentials when this same adapter changes from wlx<MAC> to wlan1.
# Do not migrate profiles for a different adapter or profiles bound to wlan0.
if [[ $mode == usb && $iface == wlan1 ]]; then
    mac=$(cat "/sys/class/net/$iface/address")
    if [[ $mac =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; then
        old_iface="wlx${mac//:/}"
        profiles=$(nmcli -g UUID connection show)
        while IFS= read -r uuid; do
            [[ -n $uuid ]] || continue
            type=$(nmcli -g connection.type connection show uuid "$uuid")
            [[ $type == 802-11-wireless ]] || continue
            bound=$(nmcli -g connection.interface-name connection show uuid "$uuid")
            [[ ${bound,,} == ${old_iface,,} ]] || continue
            # Interface names are unambiguous here; keep all MAC/security/AP settings.
            nmcli connection modify uuid "$uuid" connection.interface-name "$iface"
            echo "Migrated Wi-Fi profile $uuid: $bound -> $iface"
        done <<< "$profiles"
    fi
fi
for path in /sys/class/net/*; do
    name=${path##*/}
    wireless "$name" || continue
    [[ $name == "$iface" ]] && continue
    nmcli device set "$name" managed no
    ip link set dev "$name" down
done
systemctl restart wifi-reset.service
trap - EXIT
echo "Saved: $iface. Driver/firmware must already be installed."
echo "Connect: sudo nmcli --ask device wifi connect SSID ifname $iface"
echo 'Existing active AP/client connections on the selected interface are preserved.'
