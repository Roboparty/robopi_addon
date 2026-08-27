#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# Only reconnect the selected adapter; never replace an active AP.
set -u
CHECK_INTERVAL=${CHECK_INTERVAL:-30}
FAIL_THRESHOLD=${FAIL_THRESHOLD:-3}
WIFI_INTERFACE=${WIFI_INTERFACE:-wlan0}
log() { echo "wifi-reset-monitor: $*"; }
healthy() {
    local state
    state=$(nmcli -g GENERAL.STATE device show "$WIFI_INTERFACE" 2>/dev/null) || return 1
    [[ $state == 100* ]] && return 0
    iw dev "$WIFI_INTERFACE" info 2>/dev/null | grep -qE '^[[:space:]]*type AP$'
}
reconnect() {
    local uuid type mode auto bound
    while IFS=: read -r uuid type; do
        [[ $type == 802-11-wireless ]] || continue
        mode=$(nmcli -g 802-11-wireless.mode connection show uuid "$uuid") || continue
        [[ -z $mode || $mode == infrastructure ]] || continue
        auto=$(nmcli -g connection.autoconnect connection show uuid "$uuid") || continue
        [[ $auto == yes ]] || continue
        bound=$(nmcli -g connection.interface-name connection show uuid "$uuid") || continue
        [[ -z $bound || $bound == "$WIFI_INTERFACE" ]] || continue
        healthy && return 0
        log "Reconnecting $WIFI_INTERFACE using profile $uuid"
        nmcli --wait 20 connection up uuid "$uuid" ifname "$WIFI_INTERFACE" && return 0
    done < <(nmcli -t -f UUID,TYPE connection show)
    return 1
}
fail_count=0
trap 'exit 0' TERM INT
log "Monitoring $WIFI_INTERFACE (no fallback to another adapter)"
while :; do
    if [[ ! -d /sys/class/net/$WIFI_INTERFACE/wireless ]]; then
        log "Waiting for selected adapter $WIFI_INTERFACE (possibly unplugged)"
    elif healthy; then
        fail_count=0
        rm -f /run/roboparty/wifi-failure
    else
        state=$(nmcli -g GENERAL.STATE device show "$WIFI_INTERFACE" 2>/dev/null)
        case "$state" in
            10\ *|20\ *|40\ *|50\ *|60\ *|70\ *|80\ *|90\ *)
                # Respect unmanaged/unavailable devices and ongoing activation.
                ;;
            *)
                if reconnect; then
                    fail_count=0
                else
                    ((fail_count+=1))
                    if ((fail_count >= FAIL_THRESHOLD)); then
                        mkdir -p /run/roboparty
                        printf '%s: reconnect failed on %s\n' "$(date -Is)" "$WIFI_INTERFACE" > /run/roboparty/wifi-failure
                        log "Reconnect failed on $WIFI_INTERFACE"
                        fail_count=0
                    fi
                fi ;;
        esac
    fi
    sleep "$CHECK_INTERVAL"
done
