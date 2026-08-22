#!/bin/bash
# SPDX-License-Identifier: GPL-3.0

set -euo pipefail

DEFAULT_INTERFACE="${ETHERNET_INTERFACE:-enP4p65s0}"
CPUINFO_FILE="${ROBOPI_CPUINFO_FILE:-/proc/cpuinfo}"

usage() {
    cat <<'EOF'
Usage: robopi-ethernet-mac <check|status|apply|restore> [interface]

Commands:
  check    Derive and print the stable MAC without changing the network
  status   Show the derived MAC and current NetworkManager state
  apply    Apply the derived MAC and request a new DHCP lease
  restore  Restore NetworkManager's permanent-MAC policy

The default interface is enP4p65s0. Run apply and restore from a serial
console because reactivating the connection interrupts Ethernet access.
EOF
}

die() {
    printf 'robopi-ethernet-mac: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

read_chip_id() {
    local chip_id

    [ -r "$CPUINFO_FILE" ] || die "cannot read $CPUINFO_FILE"
    chip_id=$(awk '/^Serial[[:space:]]*:/{print $3; exit}' "$CPUINFO_FILE")
    chip_id=${chip_id,,}

    [ -n "$chip_id" ] || die "RK3588 Chip ID is empty; no changes were made"
    [[ "$chip_id" =~ ^[0-9a-f]+$ ]] || die "invalid RK3588 Chip ID: $chip_id"
    [[ "$chip_id" =~ [1-9a-f] ]] || die "RK3588 Chip ID is all zero; no changes were made"

    printf '%s' "$chip_id"
}

derive_mac() {
    local chip_id="$1"
    local hash first_byte

    hash=$(printf 'roboparty-ethernet-v1:%s' "$chip_id" | sha256sum)
    hash=${hash:0:12}
    first_byte=$(printf '%02x' "$(( (16#${hash:0:2} & 16#fc) | 16#02 ))")
    printf '%s:%s:%s:%s:%s:%s' \
        "$first_byte" "${hash:2:2}" "${hash:4:2}" \
        "${hash:6:2}" "${hash:8:2}" "${hash:10:2}"
}

derive_and_verify() {
    local chip_id="$1"
    local derived check

    derived=$(derive_mac "$chip_id")
    check=$(derive_mac "$chip_id")
    [ "$derived" = "$check" ] || die "derived MAC stability check failed"

    printf '%s' "$derived"
}

connection_uuid() {
    local interface="$1"
    local uuid

    uuid=$(nmcli -g GENERAL.CON-UUID device show "$interface" 2>/dev/null || true)
    [ -n "$uuid" ] || die "no active NetworkManager connection for $interface"
    printf '%s' "$uuid"
}

print_identity() {
    local chip_id="$1"
    local mac="$2"

    printf 'Chip ID:     %s\n' "$chip_id"
    printf 'Derived MAC: %s\n' "$mac"
    printf 'Check MAC:   %s\n' "$(derive_mac "$chip_id")"
}

show_status() {
    local interface="$1"
    local uuid

    require_command ip
    require_command nmcli
    ip link show "$interface" >/dev/null 2>&1 || die "network interface not found: $interface"
    uuid=$(connection_uuid "$interface")

    printf '\nNetwork interface:\n'
    ip -br link show "$interface"
    ip -br addr show "$interface"
    printf '\nNetworkManager device:\n'
    nmcli -f GENERAL.DEVICE,GENERAL.HWADDR,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY \
        device show "$interface"
    printf '\nNetworkManager connection:\n'
    nmcli -f connection.id,connection.uuid,802-3-ethernet.cloned-mac-address,ipv4.method,ipv4.dhcp-client-id \
        connection show uuid "$uuid"
}

reactivate() {
    local uuid="$1"
    local interface="$2"

    nmcli connection down uuid "$uuid" >/dev/null 2>&1 || true
    nmcli --wait 30 connection up uuid "$uuid" ifname "$interface"
}

apply_mac() {
    local interface="$1"
    local mac="$2"
    local uuid

    [ "${EUID:-$(id -u)}" -eq 0 ] || die "apply must be run as root"
    require_command ip
    require_command nmcli
    ip link show "$interface" >/dev/null 2>&1 || die "network interface not found: $interface"
    uuid=$(connection_uuid "$interface")

    printf '\nApplying %s to %s (connection %s).\n' "$mac" "$interface" "$uuid"
    nmcli connection modify uuid "$uuid" \
        802-3-ethernet.cloned-mac-address "$mac" \
        ipv4.method auto \
        ipv4.dhcp-client-id mac

    if ! reactivate "$uuid" "$interface"; then
        printf 'Activation failed; restoring the permanent-MAC policy.\n' >&2
        nmcli connection modify uuid "$uuid" \
            802-3-ethernet.cloned-mac-address permanent \
            ipv4.dhcp-client-id ""
        nmcli --wait 30 connection up uuid "$uuid" ifname "$interface" || true
        die "failed to activate the derived MAC; the default policy was restored"
    fi

    show_status "$interface"
}

restore_mac() {
    local interface="$1"
    local uuid

    [ "${EUID:-$(id -u)}" -eq 0 ] || die "restore must be run as root"
    require_command ip
    require_command nmcli
    ip link show "$interface" >/dev/null 2>&1 || die "network interface not found: $interface"
    uuid=$(connection_uuid "$interface")

    nmcli connection modify uuid "$uuid" \
        802-3-ethernet.cloned-mac-address permanent \
        ipv4.dhcp-client-id ""
    reactivate "$uuid" "$interface"
    show_status "$interface"
}

main() {
    local command="${1:-}"
    local interface="${2:-$DEFAULT_INTERFACE}"
    local chip_id mac

    case "$command" in
        check|status|apply)
            require_command awk
            require_command sha256sum
            chip_id=$(read_chip_id)
            mac=$(derive_and_verify "$chip_id")
            print_identity "$chip_id" "$mac"
            ;;
        restore)
            ;;
        -h|--help|help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac

    case "$command" in
        check) ;;
        status) show_status "$interface" ;;
        apply) apply_mac "$interface" "$mac" ;;
        restore) restore_mac "$interface" ;;
    esac
}

main "$@"
