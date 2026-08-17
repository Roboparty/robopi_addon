#!/bin/bash
#==============================================================================
# HPM Firmware Flasher — RoboParty
#
# Wraps hpmtool.py to flash a firmware image to the HPM5E00 via USB HID.
# The chip model, connection mode and flash address are preset so the user
# only needs to supply the firmware binary.
#
# Usage:
#   flash_hpm.sh <firmware.bin>
#
# Options (overridable via environment):
#   HPMTOOL       path to hpmtool.py (default: hpmtool on PATH)
#   HPM_CHIP      target chip      (default: hpm5e00)
#   HPM_ADDR      flash address    (default: 0x80000400)
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "${HPMTOOL:-}" ]; then
    HPMTOOL="$HPMTOOL"
elif [ -x "$SCRIPT_DIR/hpmtool" ]; then
    HPMTOOL="$SCRIPT_DIR/hpmtool"
elif [ -x "$SCRIPT_DIR/hpmtool.py" ]; then
    HPMTOOL="$SCRIPT_DIR/hpmtool.py"
else
    HPMTOOL="hpmtool"
fi

HPM_CHIP="${HPM_CHIP:-hpm5e00}"
HPM_ADDR="${HPM_ADDR:-0x80000400}"

FIRMWARE="${1:-}"

usage() {
    echo "Usage: $0 <firmware.bin>" >&2
    echo "  Flashes firmware to HPM chip via USB HID (chip=${HPM_CHIP}, addr=${HPM_ADDR})" >&2
    exit 1
}

if [ -z "$FIRMWARE" ]; then
    usage
fi

if [ ! -f "$FIRMWARE" ]; then
    echo "Error: firmware file not found: $FIRMWARE" >&2
    exit 1
fi

if ! command -v "$HPMTOOL" >/dev/null 2>&1; then
    echo "Error: hpmtool not found. Set HPMTOOL to the hpmtool.py path." >&2
    exit 1
fi

echo "Flashing $FIRMWARE to $HPM_CHIP @ $HPM_ADDR (USB HID)..."
"$HPMTOOL" -u -c "$HPM_CHIP" write_flash "$HPM_ADDR" "$FIRMWARE"
echo "Done."
