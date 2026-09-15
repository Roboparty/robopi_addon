#!/bin/bash
# Non-mutating tests: mock all commands that can touch hardware.
set -eu
cd "$(dirname "$0")/.."
udevadm() { printf '%s\n' 'ID_VENDOR_ID=0000'; }
eject() { echo 'ERROR: unrelated disk ejected'; return 1; }

out=$( . scripts/robopi-usb-wifi-init.sh )
[[ "$out" == *'preparation complete'* && "$out" != *ERROR* ]]

echo 'PASS: BSP driver preparation completed; unrelated disks untouched'
