#!/bin/bash
# Test a copy with sandboxed paths and mocked hardware commands.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d)
export fixture
mkdir -p "$fixture/etc/roboparty" "$fixture/sys/class/net" "$fixture/run"
sed -e "s|/etc/|$fixture/etc/|g" -e "s|/sys/class/net|$fixture/sys/class/net|g" -e "s|/run/|$fixture/run/|g" -e 's/\[\[ $EUID == 0 \]\]/true/' scripts/robopi-wifi-select.sh > "$fixture/select.sh"
readlink() { case "$*" in *wlx*) echo '/devices/usb1/1-1';; *) echo '/devices/platform/wifi';; esac; }
flock() { :; }
sleep() { :; }
systemctl() { echo "systemctl $*" >> "$fixture/calls"; }
ip() { echo "ip $*" >> "$fixture/calls"; }
nmcli() {
    echo "nmcli $*" >> "$fixture/calls"
    if [[ $* == '-g GENERAL.DEVICE '* && ${not_ready:-no} == yes ]]; then return 1; fi
    return 0
}
iw() { if [[ ${ap_iface:-none} == "$2" ]]; then echo ' type AP'; fi; return 0; }
export -f readlink flock sleep systemctl ip nmcli iw
run() { bash "$fixture/select.sh" "$@"; }
mkdir -p "$fixture/sys/class/net/wlan0/wireless" "$fixture/sys/class/net/wlxNEW/wireless"
run auto-usb
grep -qx 'WIFI_INTERFACE=wlxNEW' "$fixture/etc/roboparty/wifi-interface"
grep -q 'nmcli device set wlan0 managed no' "$fixture/calls"
mkdir -p "$fixture/sys/class/net/wlxSECOND/wireless"
run auto-usb
grep -qx 'WIFI_INTERFACE=wlxNEW' "$fixture/etc/roboparty/wifi-interface"
printf 'WIFI_INTERFACE=missing\n' > "$fixture/etc/roboparty/wifi-interface"
run auto-usb
grep -qx 'WIFI_INTERFACE=missing' "$fixture/etc/roboparty/wifi-interface"
run onboard wlan0
test -e "$fixture/etc/roboparty/wifi-auto-disabled"
run auto-usb
grep -qx 'WIFI_INTERFACE=wlan0' "$fixture/etc/roboparty/wifi-interface"
run usb wlxNEW
test ! -e "$fixture/etc/roboparty/wifi-auto-disabled"
export ap_iface=wlan0
out=$(run auto-usb)
[[ $out == *'AP active on wlan0'* ]]
unset ap_iface
export not_ready=yes
if run usb wlxSECOND; then echo 'FAIL: expected discovery failure'; exit 1; fi
grep -qx 'WIFI_INTERFACE=wlxNEW' "$fixture/etc/roboparty/wifi-interface"
unset not_ready
echo "PASS: USB selection, ambiguity, manual override, AP guard, readiness failure ($fixture)"
