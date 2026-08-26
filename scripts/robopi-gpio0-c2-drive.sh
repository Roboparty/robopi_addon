#!/bin/sh
# SPDX-License-Identifier: GPL-3.0
# Copyright (C) 2025-2026 fanxiaobinggit
set -eu

FDT_ENV=${FDT_ENV:-/boot/orangepiEnv.txt}
DTB_ROOT=${DTB_ROOT:-/boot/dtb}
EXPECTED_MODEL=${EXPECTED_MODEL:-RK3588S Orange Pi CM5}
BACKUP_SUFFIX=.robopi-before-gpio0-c2-drive

die()
{
    echo "robopi-gpio0-c2-drive: $*" >&2
    exit 1
}

need_root()
{
    [ "$(id -u)" -eq 0 ] || die "run this command with sudo"
}

need_tool()
{
    command -v "$1" >/dev/null 2>&1 || die "required command is missing: $1"
}

board_model()
{
    tr -d '\000' </proc/device-tree/model 2>/dev/null || true
}

find_dtb()
{
    [ -r "$FDT_ENV" ] || die "cannot read $FDT_ENV"
    fdtfile=$(sed -n 's/^[[:space:]]*fdtfile=//p' "$FDT_ENV" | tail -n 1)
    [ -n "$fdtfile" ] || die "fdtfile is not configured in $FDT_ENV"
    case "$fdtfile" in
        /*) dtb=$fdtfile ;;
        *)  dtb=$DTB_ROOT/$fdtfile ;;
    esac
    [ -f "$dtb" ] || die "configured DTB does not exist: $dtb"
    printf '%s\n' "$dtb"
}

extract_level5_phandle()
{
    awk '
        /pcfg-pull-down-drv-level-5[[:space:]]*{/ { inside = 1; next }
        inside && /phandle[[:space:]]*=/ {
            line = $0
            sub(/^.*<0x/, "", line)
            sub(/>.*$/, "", line)
            print "0x" line
            exit
        }
        inside && /};/ { inside = 0 }
    ' "$1"
}

show_status()
{
    dtb=$(find_dtb)
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
    dtc -q -I dtb -O dts "$dtb" -o "$tmpdir/current.dts"
    level5=$(extract_level5_phandle "$tmpdir/current.dts")
    [ -n "$level5" ] || die "Level5 pin configuration was not found in $dtb"
    pin_line=$(sed -n '/dual-battery-c2-pin[[:space:]]*{/,/};/ { /rockchip,pins[[:space:]]*=/p; }' "$tmpdir/current.dts")
    [ -n "$pin_line" ] || die "dual-battery-c2-pin was not found in $dtb"

    echo "Board model: $(board_model)"
    echo "Boot DTB:    $dtb"
    echo "Level5:     $level5 (maximum GPIO0_C drive, approximately 25 ohms)"
    echo "GPIO0_C2:   $pin_line"
    case "$pin_line" in
        *" $level5>"*) echo "Status:      maximum drive is configured" ;;
        *)             echo "Status:      maximum drive is not configured" ;;
    esac
}

apply_drive()
{
    need_root
    need_tool dtc
    model=$(board_model)
    case "$model" in
        *"$EXPECTED_MODEL"*) ;;
        *) die "unsupported board model: ${model:-unknown}" ;;
    esac

    dtb=$(find_dtb)
    backup=$dtb$BACKUP_SUFFIX
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
    dtc -q -I dtb -O dts "$dtb" -o "$tmpdir/source.dts"
    level5=$(extract_level5_phandle "$tmpdir/source.dts")
    [ -n "$level5" ] || die "Level5 pin configuration was not found in $dtb"

    old_line=$(sed -n '/dual-battery-c2-pin[[:space:]]*{/,/};/ { /rockchip,pins[[:space:]]*=/p; }' "$tmpdir/source.dts")
    [ -n "$old_line" ] || die "dual-battery-c2-pin was not found in $dtb"
    case "$old_line" in
        *" $level5>"*)
            echo "GPIO0_C2 already uses maximum drive ($level5)."
            exit 0
            ;;
    esac

    awk -v target="$level5" '
        /dual-battery-c2-pin[[:space:]]*{/ { inside = 1 }
        inside && /rockchip,pins[[:space:]]*=/ {
            if ($0 !~ /<0x00 0x12 0x00 0x[0-9a-fA-F]+>/) {
                print "unexpected GPIO0_C2 rockchip,pins format" > "/dev/stderr"
                exit 2
            }
            sub(/<0x00 0x12 0x00 0x[0-9a-fA-F]+>/,
                "<0x00 0x12 0x00 " target ">")
            changed++
        }
        { print }
        inside && /};/ { inside = 0 }
        END {
            if (changed != 1) {
                print "expected exactly one GPIO0_C2 pin change" > "/dev/stderr"
                exit 3
            }
        }
    ' "$tmpdir/source.dts" >"$tmpdir/patched.dts" ||
        die "could not update the GPIO0_C2 pin configuration"

    dtc -q -I dts -O dtb "$tmpdir/patched.dts" -o "$tmpdir/patched.dtb"
    dtc -q -I dtb -O dts "$tmpdir/patched.dtb" -o "$tmpdir/verify.dts"
    verify_line=$(sed -n '/dual-battery-c2-pin[[:space:]]*{/,/};/ { /rockchip,pins[[:space:]]*=/p; }' "$tmpdir/verify.dts")
    case "$verify_line" in
        *" $level5>"*) ;;
        *) die "compiled DTB verification failed" ;;
    esac

    if [ ! -e "$backup" ]; then
        cp -a "$dtb" "$backup"
        echo "Backup:      $backup"
    else
        echo "Backup kept: $backup"
    fi
    install -m 0644 "$tmpdir/patched.dtb" "$dtb.new"
    mv -f "$dtb.new" "$dtb"
    sync
    echo "Installed:   $dtb"
    echo "GPIO0_C2:    maximum drive Level5 (approximately 25 ohms)"
    echo "Reboot is required: sudo reboot"
}

restore_drive()
{
    need_root
    dtb=$(find_dtb)
    backup=$dtb$BACKUP_SUFFIX
    [ -f "$backup" ] || die "backup does not exist: $backup"
    install -m 0644 "$backup" "$dtb.new"
    mv -f "$dtb.new" "$dtb"
    sync
    echo "Restored: $dtb"
    echo "Reboot is required: sudo reboot"
}

case "${1:-}" in
    status)  need_tool dtc; show_status ;;
    apply)   apply_drive ;;
    restore) restore_drive ;;
    *)
        echo "Usage: robopi-gpio0-c2-drive {status|apply|restore}" >&2
        exit 2
        ;;
esac
