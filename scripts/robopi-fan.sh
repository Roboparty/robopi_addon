#!/bin/sh
# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2025-2026 fanxiaobinggit

set -eu

GPIO=63                 # GPIO1_D7 = 1 * 32 + 3 * 8 + 7
GPIO_DIR="/sys/class/gpio/gpio${GPIO}"
EXPORT="/sys/class/gpio/export"

usage()
{
    echo "Usage: sudo robopi-fan {on|off|status}" >&2
    exit 2
}

require_root()
{
    if [ "$(id -u)" -ne 0 ]; then
        echo "robopi-fan: root privileges are required; run with sudo" >&2
        exit 1
    fi
}

ensure_exported()
{
    if [ ! -d "$GPIO_DIR" ]; then
        if ! printf '%s\n' "$GPIO" > "$EXPORT" 2>/dev/null; then
            echo "robopi-fan: cannot request GPIO1_D7 (GPIO${GPIO}); it may be owned by another driver" >&2
            exit 1
        fi

        count=0
        while [ ! -e "$GPIO_DIR/direction" ] && [ "$count" -lt 50 ]; do
            sleep 0.01
            count=$((count + 1))
        done
    fi

    if [ ! -e "$GPIO_DIR/direction" ]; then
        echo "robopi-fan: GPIO${GPIO} sysfs interface did not appear" >&2
        exit 1
    fi
}

set_fan()
{
    level=$1
    label=$2

    # The high/low direction operation changes direction and initial value
    # atomically, avoiding a short opposite-level pulse.
    printf '%s\n' "$level" > "$GPIO_DIR/direction"
    actual=$(cat "$GPIO_DIR/value")
    echo "FAN_SW ${label}: GPIO1_D7=GPIO${GPIO}, value=${actual}"
}

show_status()
{
    if [ ! -d "$GPIO_DIR" ]; then
        echo "FAN_SW status: unclaimed (fan state is controlled by the pin default)"
        return
    fi

    direction=$(cat "$GPIO_DIR/direction")
    value=$(cat "$GPIO_DIR/value")
    if [ "$direction" = "out" ] && [ "$value" = "1" ]; then
        state=on
    elif [ "$direction" = "out" ] && [ "$value" = "0" ]; then
        state=off
    else
        state=unknown
    fi
    echo "FAN_SW status: ${state} (GPIO1_D7=GPIO${GPIO}, direction=${direction}, value=${value})"
}

[ "$#" -eq 1 ] || usage

case "$1" in
    on)
        require_root
        ensure_exported
        set_fan high ON
        ;;
    off)
        require_root
        ensure_exported
        set_fan low OFF
        ;;
    status)
        show_status
        ;;
    *)
        usage
        ;;
esac

