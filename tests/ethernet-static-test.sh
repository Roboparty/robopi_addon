#!/bin/bash
# Test a copy with sandboxed paths and mocked network commands.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d)
export fixture
mkdir -p "$fixture/etc"
# Sandbox resolv.conf and neutralize the root check (addressed by line so no
# regex-escaping pitfalls); everything else is mocked below.
root_check_line=$(grep -n 'apply must be run as root' scripts/robopi-ethernet-static.sh | head -1 | cut -d: -f1)
[ -n "$root_check_line" ] || { echo 'FAIL: root check line not found'; exit 1; }
sed -e "s|/etc/resolv.conf|$fixture/etc/resolv.conf|g" \
    -e "${root_check_line}s/.*/    true/" \
    scripts/robopi-ethernet-static.sh > "$fixture/static.sh"

sleep() { :; }
ip() {
    if [[ "$1 ${2:-}" == 'link show' ]]; then
        [[ ${iface_missing:-no} != yes ]]
        return
    fi
    echo "ip $*" >> "$fixture/calls"
}
nmcli() { echo "nmcli $*" >> "$fixture/calls"; }
resolvectl() {
    if [[ $1 == status ]]; then
        [[ ${resolved_inactive:-no} != yes ]]
        return
    fi
    echo "resolvectl $*" >> "$fixture/calls"
}
ping() {
    echo "ping $*" >> "$fixture/calls"
    [[ ${ping_fail:-no} != yes ]]
}
export -f sleep ip nmcli resolvectl ping
run() { bash "$fixture/static.sh" "$@"; }
line_of() { grep -n -F "$1" "$fixture/calls" | head -1 | cut -d: -f1; }

# Apply with systemd-resolved active: full SOP sequence, NM released first.
: > "$fixture/calls"
run apply
grep -qx 'nmcli general reload' "$fixture/calls"
grep -qx 'nmcli device set enP4p65s0 managed no' "$fixture/calls"
grep -qx 'ip link set dev enP4p65s0 up' "$fixture/calls"
grep -qx 'ip -4 addr flush dev enP4p65s0' "$fixture/calls"
grep -qx 'ip addr add 192.168.13.1/24 dev enP4p65s0' "$fixture/calls"
grep -qx 'ip route replace default via 192.168.13.10 dev enP4p65s0' "$fixture/calls"
grep -qx 'resolvectl dns enP4p65s0 223.5.5.5 8.8.8.8' "$fixture/calls"
grep -qx 'resolvectl domain enP4p65s0 ~.' "$fixture/calls"
grep -qx 'resolvectl flush-caches' "$fixture/calls"
managed_line=$(line_of 'nmcli device set enP4p65s0 managed no')
addr_line=$(line_of 'ip addr add')
[[ $managed_line -lt $addr_line ]] || { echo 'FAIL: NM not released before configuring'; exit 1; }

# Idempotent: a second apply repeats the same deterministic sequence.
run apply
test "$(grep -c 'ip addr add' "$fixture/calls")" = 2
test "$(grep -c 'ip -4 addr flush' "$fixture/calls")" = 2

# Environment overrides from /etc/default reach every command.
: > "$fixture/calls"
export ETHERNET_IP=10.0.0.5/24 ETHERNET_GATEWAY=10.0.0.1 ETHERNET_DNS1=1.1.1.1 ETHERNET_DNS2=
run apply
unset ETHERNET_IP ETHERNET_GATEWAY ETHERNET_DNS1 ETHERNET_DNS2
grep -qx 'ip addr add 10.0.0.5/24 dev enP4p65s0' "$fixture/calls"
grep -qx 'ip route replace default via 10.0.0.1 dev enP4p65s0' "$fixture/calls"
grep -qx 'resolvectl dns enP4p65s0 1.1.1.1' "$fixture/calls"

# Without systemd-resolved the DNS fallback replaces the resolved stub
# symlink with a regular resolv.conf. (Git Bash ln -s copies instead of
# linking; on Linux this exercises the symlink case for real.)
: > "$fixture/calls"
rm -f "$fixture/etc/resolv.conf"
printf 'nameserver 9.9.9.9\n' > "$fixture/etc/stub-resolv.conf"
ln -s "$fixture/etc/stub-resolv.conf" "$fixture/etc/resolv.conf"
export resolved_inactive=yes
run apply
unset resolved_inactive
test ! -L "$fixture/etc/resolv.conf"
grep -qx 'nameserver 223.5.5.5' "$fixture/etc/resolv.conf"
grep -qx 'nameserver 8.8.8.8' "$fixture/etc/resolv.conf"

# A missing interface must fail the service instead of configuring blind.
: > "$fixture/calls"
export iface_missing=yes
if out=$(run apply 2>&1); then echo 'FAIL: expected interface wait failure'; exit 1; fi
[[ $out == *'network interface not found: enP4p65s0'* ]]
! grep -q 'addr add' "$fixture/calls"
unset iface_missing

# check reports the SOP verification targets; failures exit nonzero.
: > "$fixture/calls"
out=$(run check)
[[ $out == *'PASS: ping 192.168.13.10'* ]]
[[ $out == *'PASS: ping 8.8.8.8'* ]]
[[ $out == *'PASS: ping baidu.com'* ]]
export ping_fail=yes
if run check >/dev/null 2>&1; then echo 'FAIL: expected connectivity failure'; exit 1; fi
unset ping_fail

# Unknown or missing subcommands show usage instead of acting.
if run 2>/dev/null; then echo 'FAIL: expected usage exit'; exit 1; fi
if run frobnicate 2>/dev/null; then echo 'FAIL: expected usage exit'; exit 1; fi
run help >/dev/null

# Static contract checks on the shipped wiring.
unit=etc/systemd/system/robopi-ethernet-static.service
grep -Fq 'EnvironmentFile=-/etc/default/robopi-ethernet-static' "$unit"
grep -Fq 'ExecStart=/opt/roboparty/bin/robopi-ethernet-static apply' "$unit"
grep -Fq 'WantedBy=multi-user.target' "$unit"
nmconf=etc/NetworkManager/conf.d/80-robopi-ethernet-static.conf
grep -Fq 'match-device=interface-name:enP4p65s0' "$nmconf"
grep -Fq 'managed=0' "$nmconf"
grep -Fq 'ETHERNET_GATEWAY=192.168.13.10' etc/default/robopi-ethernet-static
grep -Fq 'systemctl enable robopi-ethernet-static.service' debian/postinst
grep -Fq 'robopi-ethernet-static' Makefile
echo "PASS: apply ordering, overrides, DNS fallback, wait failure, checks and wiring contract ($fixture)"
