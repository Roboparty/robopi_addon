#!/bin/bash
# Non-mutating tests: mock all commands that can touch hardware.
set -eu
cd "$(dirname "$0")/.."
uname() { printf '%s\n' "$mock_kernel"; }
modprobe() { printf 'MODPROBE:%s\n' "$1"; return "${mock_modprobe_rc:-0}"; }
udevadm() { printf '%s\n' 'ID_VENDOR_ID=0000'; }
eject() { echo 'ERROR: unrelated disk ejected'; return 1; }

mock_kernel=unrelated-kernel
out=$( . scripts/robopi-usb-wifi-init.sh 2>&1 )
[[ "$out" == *'skipping current kernel'* && "$out" != *MODPROBE* ]]

mock_kernel=6.1.99-rt36-rockchip-rk3588
out=$( . scripts/robopi-usb-wifi-init.sh )
[[ "$out" == *MODPROBE:aic_load_fw* && "$out" == *MODPROBE:aic8800_fdrv* ]]
[[ "$out" == *'preparation complete'* && "$out" != *ERROR* ]]

echo 'PASS: wrong kernel skipped; matching modules loaded; unrelated disks untouched'
