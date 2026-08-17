#!/bin/bash
# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2025-2026 YutongChenVictor
#==============================================================================
# HPM Reset Monitor — RoboParty EtherCAT CANFD Master
#
# Continuously monitors the USB enumeration state of the HPM device
# (roboto_usb4can, 1209:2323). If the USB device drops offline or fails
# to enumerate, toggles the USB hub reset GPIO to hardware-reset the HPM.
#
# Device:  roboto_usb4can (wentytwenty)
#          VID=1209, PID=2323
#          Kernel driver: gs_usb
#
# GPIO4_B5 on RK3588 (gpio-leds, label "usb_hub_reset"):
#   Sysfs:  /sys/class/leds/usb_hub_reset/brightness
#   brightness 1 = GPIO high = hub reset (Q21 on → XRSTJ low → hub stopped)
#   brightness 0 = GPIO low  = hub enabled (normal, default state)
#==============================================================================

set -e

# ---- Configurable parameters (overridable via systemd EnvironmentFile) -------
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"       # Check interval (seconds)
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"       # Consecutive failure threshold
RESET_HOLD_TIME="${RESET_HOLD_TIME:-0.5}"   # Reset pulse duration (seconds)
POST_RESET_WAIT="${POST_RESET_WAIT:-15}"    # Wait time after reset (seconds)
LOG_TAG="hpm-reset-monitor"

# USB hub reset LED (gpio-leds) sysfs path
HUB_RESET_LED="/sys/class/leds/usb_hub_reset/brightness"

# USB device identification (roboto_usb4can)
HPM_VID="${HPM_VID:-1209}"
HPM_PID="${HPM_PID:-2323}"

# ---- Logging -----------------------------------------------------------------
log_msg() {
    local level="${1:-INFO}"
    shift
    logger -t "$LOG_TAG" -p "daemon.${level}" "$*"
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

# ---- USB hub reset LED control ----------------------------------------------
hub_reset_on() {
    echo 1 > "$HUB_RESET_LED" 2>/dev/null || {
        log_msg "ERR" "Cannot write $HUB_RESET_LED (usb_hub_reset LED not found)"
        return 1
    }
}

hub_reset_off() {
    echo 0 > "$HUB_RESET_LED" 2>/dev/null || true
}

# ---- HPM USB enumeration detection -------------------------------------------
# Returns 0 = HPM USB device enumerated
# Returns 1 = HPM device not found (needs reset)
check_hpm_usb() {
    # Method 1: lsusb — most reliable
    if command -v lsusb &>/dev/null; then
        if lsusb -d "${HPM_VID}:${HPM_PID}" 2>/dev/null | grep -q .; then
            return 0
        fi
    fi

    # Method 2: sysfs USB device tree — no extra tools needed
    # Search /sys/bus/usb/devices/ for matching idVendor/idProduct
    for dev in /sys/bus/usb/devices/*/; do
        local vid pid
        vid="$(cat "${dev}idVendor" 2>/dev/null || true)"
        pid="$(cat "${dev}idProduct" 2>/dev/null || true)"
        if [ "$vid" = "$HPM_VID" ] && [ "$pid" = "$HPM_PID" ]; then
            return 0
        fi
    done

    # Method 3: /proc/bus/usb/devices (legacy kernel compatibility)
    if [ -f /proc/bus/usb/devices ]; then
        if grep -q "Vendor=${HPM_VID}.*ProdID=${HPM_PID}" /proc/bus/usb/devices 2>/dev/null; then
            return 0
        fi
    fi

    log_msg "WARN" "HPM USB device ${HPM_VID}:${HPM_PID} (roboto_usb4can) not enumerated"
    return 1
}

# ---- Reset operation ---------------------------------------------------------
pulse_reset() {
    log_msg "WARN" "=== Triggering USB hub reset (GPIO4_B5, usb_hub_reset LED) ==="

    if ! hub_reset_on; then
        log_msg "ERR" "USB hub reset failed, LED unavailable"
        return 1
    fi
    sleep "$RESET_HOLD_TIME"
    hub_reset_off

    log_msg "INFO" "Reset pulse complete (${RESET_HOLD_TIME}s), waiting ${POST_RESET_WAIT}s for HPM re-enumeration..."
    sleep "$POST_RESET_WAIT"
}

# ---- Cleanup -----------------------------------------------------------------
cleanup() {
    log_msg "INFO" "HPM Reset Monitor shutting down..."
    hub_reset_off
    log_msg "INFO" "HPM Reset Monitor stopped"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# ---- Main loop ---------------------------------------------------------------
main() {
    log_msg "INFO" "=============================================="
    log_msg "INFO" "HPM Reset Monitor starting"
    log_msg "INFO" "  HPM device:      USB ${HPM_VID}:${HPM_PID} (roboto_usb4can)"
    log_msg "INFO" "  Hub reset:       usb_hub_reset LED (GPIO4_B5)"
    log_msg "INFO" "  Check interval:   ${CHECK_INTERVAL}s"
    log_msg "INFO" "  Failure threshold: ${FAIL_THRESHOLD} consecutive failures"
    log_msg "INFO" "  Reset pulse:      ${RESET_HOLD_TIME}s"
    log_msg "INFO" "  Post-reset wait:  ${POST_RESET_WAIT}s"
    log_msg "INFO" "=============================================="

    if [ ! -f "$HUB_RESET_LED" ]; then
        log_msg "ERR" "usb_hub_reset LED not found ($HUB_RESET_LED), check device tree"
        exit 1
    fi

    # Ensure hub is in normal (enabled) state on startup
    hub_reset_off

    local fail_count=0

    while true; do
        if check_hpm_usb; then
            if [ "$fail_count" -gt 0 ]; then
                log_msg "INFO" "HPM USB re-enumerated (${fail_count} previous failure(s))"
            fi
            fail_count=0
        else
            fail_count=$((fail_count + 1))
            log_msg "WARN" "HPM USB not enumerated (${fail_count}/${FAIL_THRESHOLD})"

            if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                log_msg "ERR" "${FAIL_THRESHOLD} consecutive HPM USB detection failures — triggering hardware reset"
                pulse_reset
                fail_count=0
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

main "$@"
