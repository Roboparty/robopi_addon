#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2025-2026 YutongChenVictor
#==============================================================================
# WiFi Reconnect Monitor — RoboParty
#
# Continuously monitors WiFi connection state in the background.
# If WiFi disconnects, automatically reconnects using locally stored
# WiFi profiles. Reports an error after 3 consecutive reconnect failures.
#
# Dependencies: NetworkManager (nmcli)
#==============================================================================

set -e

# ---- Configurable parameters (overridable via systemd Environment=) ----------
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"       # Check interval (seconds)
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"        # Consecutive failure threshold
WIFI_INTERFACE="${WIFI_INTERFACE:-wlan0}"    # WiFi interface name
LOG_TAG="wifi-reset-monitor"

# ---- Logging -----------------------------------------------------------------
log_msg() {
    local level="${1:-INFO}"
    shift
    echo "${LOG_TAG}: [$level] $*" > /dev/kmsg 2>/dev/null || true
}

# ---- WiFi connection state detection -----------------------------------------
# Returns 0 = WiFi connected
# Returns 1 = WiFi disconnected
check_wifi() {
    # Method 1: nmcli — check specific WiFi device state
    if command -v nmcli &>/dev/null; then
        local wifi_state
        wifi_state=$(nmcli -t -f GENERAL.STATE device show "$WIFI_INTERFACE" 2>/dev/null | cut -d: -f2)
        if [ "$wifi_state" = "100" ]; then
            # 100 = NM_DEVICE_STATE_ACTIVATED
            return 0
        fi
    fi

    # Method 2: iw — check if associated with an AP
    if command -v iw &>/dev/null; then
        if iw dev "$WIFI_INTERFACE" link 2>/dev/null | grep -q "Connected to"; then
            return 0
        fi
    fi

    # Method 3: check if the interface has an IP address (last resort)
    if ip addr show "$WIFI_INTERFACE" 2>/dev/null | grep -q "inet "; then
        return 0
    fi

    log_msg "WARN" "WiFi interface ${WIFI_INTERFACE} is disconnected"
    return 1
}

# ---- WiFi reconnect ----------------------------------------------------------
# Returns 0 = reconnect succeeded
# Returns 1 = reconnect failed
reconnect_wifi() {
    log_msg "INFO" "Attempting to reconnect WiFi..."

    # Method 1: use nmcli saved connections
    if command -v nmcli &>/dev/null; then
        # Ensure WiFi device is enabled
        nmcli radio wifi on 2>/dev/null || true
        nmcli device set "$WIFI_INTERFACE" managed true 2>/dev/null || true

        # Get all saved WiFi connection names
        local connections
        connections=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep ":802-11-wireless" | cut -d: -f1)

        if [ -n "$connections" ]; then
            log_msg "INFO" "Found $(echo "$connections" | wc -l) saved WiFi connection(s)"

            while IFS= read -r conn; do
                [ -z "$conn" ] && continue
                log_msg "INFO" "Trying connection: [$conn]"

                if nmcli connection up "$conn" 2>/dev/null; then
                    # Wait for DHCP to assign an IP
                    for _ in $(seq 1 15); do
                        sleep 1
                        if ip addr show "$WIFI_INTERFACE" 2>/dev/null | grep -q "inet "; then
                            log_msg "INFO" "Connected to [$conn] with IP address"
                            return 0
                        fi
                    done
                    # nmcli reported success but no IP yet, treat as success
                    log_msg "INFO" "Connected to [$conn] (waiting for IP assignment)"
                    return 0
                fi

                log_msg "WARN" "Connection [$conn] failed, trying next..."
            done <<< "$connections"
        fi
    fi

    # Method 2: wpa_cli — reconnect via wpa_supplicant
    if command -v wpa_cli &>/dev/null; then
        log_msg "INFO" "Attempting reconnect via wpa_supplicant..."
        if wpa_cli -i "$WIFI_INTERFACE" reconfigure 2>/dev/null; then
            sleep 5
            if check_wifi; then
                return 0
            fi
        fi
    fi

    # Method 3: rescan and retry
    if command -v nmcli &>/dev/null; then
        log_msg "INFO" "Rescanning WiFi networks..."
        nmcli device wifi rescan 2>/dev/null || true
        sleep 3

        # Retry all saved connections
        local retry_connections
        retry_connections=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep ":802-11-wireless" | cut -d: -f1)
        while IFS= read -r conn; do
            [ -z "$conn" ] && continue
            if nmcli connection up "$conn" 2>/dev/null; then
                log_msg "INFO" "Connected to [$conn] after rescan"
                return 0
            fi
        done <<< "$retry_connections"
    fi

    log_msg "ERR" "All reconnect methods failed"
    return 1
}

# ---- Error reporting ---------------------------------------------------------
report_failure() {
    local msg="WiFi reconnect failed! ${FAIL_THRESHOLD} consecutive attempts could not restore the connection. Please check the wireless network."
    log_msg "ERR" "$msg"

    # Write marker file for external monitoring
    mkdir -p /var/run/roboparty
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" > /var/run/roboparty/wifi-failure
}

# ---- Cleanup -----------------------------------------------------------------
cleanup() {
    log_msg "INFO" "WiFi Reset Monitor shutting down..."
    rm -f /var/run/roboparty/wifi-failure
    log_msg "INFO" "WiFi Reset Monitor stopped"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# ---- Main loop ---------------------------------------------------------------
main() {
    log_msg "INFO" "=============================================="
    log_msg "INFO" "WiFi Reset Monitor starting"
    log_msg "INFO" "  Interface:       ${WIFI_INTERFACE}"
    log_msg "INFO" "  Check interval:  ${CHECK_INTERVAL}s"
    log_msg "INFO" "  Failure threshold: ${FAIL_THRESHOLD} consecutive failures"
    log_msg "INFO" "=============================================="

    # Verify WiFi interface exists
    if ! ip link show "$WIFI_INTERFACE" &>/dev/null; then
        log_msg "WARN" "WiFi interface ${WIFI_INTERFACE} not found, attempting auto-detection..."
        local detected
        detected=$(iw dev 2>/dev/null | grep "Interface" | head -1 | awk '{print $2}')
        if [ -n "$detected" ]; then
            WIFI_INTERFACE="$detected"
            log_msg "INFO" "Auto-detected WiFi interface: ${WIFI_INTERFACE}"
        else
            log_msg "ERR" "No WiFi interface found, exiting"
            exit 1
        fi
    fi

    local fail_count=0

    while true; do
        if check_wifi; then
            if [ "$fail_count" -gt 0 ]; then
                log_msg "INFO" "WiFi connection restored (${fail_count} previous failure(s))"
            fi
            fail_count=0
            # Clear failure marker
            rm -f /var/run/roboparty/wifi-failure
        else
            fail_count=$((fail_count + 1))
            log_msg "WARN" "WiFi disconnected (${fail_count}/${FAIL_THRESHOLD})"

            # Attempt reconnect on every disconnect
            if reconnect_wifi; then
                log_msg "INFO" "WiFi reconnected successfully"
                fail_count=0
                rm -f /var/run/roboparty/wifi-failure
            elif [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                report_failure
                # Reset counter to keep monitoring (avoid spamming errors)
                fail_count=0
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

main "$@"
