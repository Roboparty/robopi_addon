#!/bin/bash
# Test a copy with sandboxed paths and mocked hardware commands.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d)
export fixture
mkdir -p "$fixture/etc/roboparty" "$fixture/sys/class/net" "$fixture/run"
sed -e "s|/etc/|$fixture/etc/|g" -e "s|/sys/class/net|$fixture/sys/class/net|g" -e "s|/run/|$fixture/run/|g" -e 's/\[\[ $EUID == 0 \]\]/true/' scripts/robopi-wifi-select.sh > "$fixture/select.sh"
readlink() { case "$*" in *wlx*|*/wlan1/*) echo '/devices/usb1/1-1';; *) echo '/devices/platform/wifi';; esac; }
udevadm() { [[ ${udev_busy:-no} != yes ]]; }
flock() { :; }
sleep() { :; }
systemctl() { echo "systemctl $*" >> "$fixture/calls"; }
ip() { echo "ip $*" >> "$fixture/calls"; }
nmcli() {
    echo "nmcli $*" >> "$fixture/calls"
    if [[ $* == '-g GENERAL.DEVICE '* && ${not_ready:-no} == yes ]]; then return 1; fi
    case "$*" in
        '-g UUID connection show') printf '%s\n' same other onboard unbound ap wired ;;
        '-g connection.type connection show uuid wired') echo 802-3-ethernet ;;
        '-g connection.type connection show uuid '*) echo 802-11-wireless ;;
        '-g connection.interface-name connection show uuid same'|'-g connection.interface-name connection show uuid ap') echo wlx6c1ff7f4425f ;;
        '-g connection.interface-name connection show uuid other') echo wlx6c1ff7e149c0 ;;
        '-g connection.interface-name connection show uuid onboard') echo wlan0 ;;
    esac
    return 0
}
iw() { if [[ ${ap_iface:-none} == "$2" ]]; then echo ' type AP'; fi; return 0; }
export -f readlink udevadm flock sleep systemctl ip nmcli iw
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
export udev_busy=yes
if run usb wlxSECOND; then echo 'FAIL: expected unsettled udev failure'; exit 1; fi
grep -qx 'WIFI_INTERFACE=wlxNEW' "$fixture/etc/roboparty/wifi-interface"
unset udev_busy
mkdir -p "$fixture/sys/class/net/wlan1/wireless"
printf '6c:1f:f7:f4:42:5f\n' > "$fixture/sys/class/net/wlan1/address"
run usb wlan1
grep -qx 'WIFI_INTERFACE=wlan1' "$fixture/etc/roboparty/wifi-interface"
grep -qx 'nmcli connection modify uuid same connection.interface-name wlan1' "$fixture/calls"
grep -qx 'nmcli connection modify uuid ap connection.interface-name wlan1' "$fixture/calls"
test "$(grep -c 'nmcli connection modify' "$fixture/calls")" = 2
! grep -q 'ip link.*name ' "$fixture/calls"
# Static contract checks; actual NAME assignment needs target-board udev testing.
rule=etc/udev/rules.d/70-robopi-usb-wifi-name.rules
test "$(grep -c '^ACTION=="add", SUBSYSTEM=="net", SUBSYSTEMS=="usb", TEST=="wireless"' "$rule")" = 2
grep -Fq 'KERNEL=="wlan1", NAME:="wlan1"' "$rule"
grep -Fq 'KERNEL!="wlan1", TEST!="/sys/class/net/wlan1", NAME:="wlan1"' "$rule"
echo "PASS: selection, AP guard, udev/discovery waits, same-adapter profile migration and naming rule contract ($fixture)"
