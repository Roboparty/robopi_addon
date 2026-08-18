#!/bin/bash
#==============================================================================
# HPM Bootrom Auto-Flasher — RoboParty EtherCAN FD
#
# Triggered by udev (hpm-autoflash.service) when the HPM bootrom USB HID
# device (VID 34b7) is detected. Flashes the newest ethercanfd firmware
# image found in /opt/roboparty/lib/firmware/ via flash_hpm.sh.
#
# See: /etc/systemd/system/hpm-autoflash.service
#      /etc/udev/rules.d/99-usb-hpm_hid.rules
#==============================================================================

set -e

FIRMWARE_DIR="/opt/roboparty/lib/firmware"
LOG_TAG="hpm-autoflash"
FLAG_FILE="/run/hpm-autoflash.done"

log_msg() {
    logger -t "$LOG_TAG" "$*"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# Run at most once per boot. After a successful flash the HPM stays in
# bootrom (it does not reboot on its own), and the hub reset performed by
# hpm-reset only re-enumerates the same bootrom device. Without this guard
# the service would flash again on every re-enumeration.
if [ -e "$FLAG_FILE" ]; then
    log_msg "Already flashed this boot ($FLAG_FILE exists), skipping"
    exit 0
fi

# Give the freshly-enumerated bootrom device a moment to settle.
sleep 2

# Select the newest firmware image by version-sorted filename.
LATEST=$(ls -1 "${FIRMWARE_DIR}"/ethercanfd_*.bin 2>/dev/null | sort -V | tail -1)
if [ -z "$LATEST" ]; then
    log_msg "No ethercanfd firmware found in ${FIRMWARE_DIR}"
    exit 1
fi

log_msg "HPM bootrom detected, auto-flashing latest firmware: $(basename "$LATEST")"

# Retry a few times; the bootrom may still be settling after enumeration.
for attempt in 1 2 3 4 5; do
    if /opt/roboparty/bin/flash_hpm.sh "$LATEST"; then
        touch "$FLAG_FILE"
        log_msg "Flash succeeded (attempt ${attempt})"
        exit 0
    fi
    log_msg "Flash attempt ${attempt} failed, retrying in 2s..."
    sleep 2
done

log_msg "All flash attempts failed"
exit 1
