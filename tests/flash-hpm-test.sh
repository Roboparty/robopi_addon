#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
printf 'firmware\n' > "$tmpdir/firmware.bin"
printf '1\n' > "$tmpdir/hpm-reset"
printf '0\n' > "$tmpdir/hpm-boot"

cat > "$tmpdir/hpmtool" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HPM_TEST_LOG"
case $* in
    *write_flash*) exit "${HPM_TEST_WRITE_STATUS:-0}" ;;
esac
EOF
chmod +x "$tmpdir/hpmtool"

run_flash() {
    HPMTOOL="$tmpdir/hpmtool" \
    HPM_RESET_LED="$tmpdir/hpm-reset" \
    HPM_BOOT_LED="$tmpdir/hpm-boot" \
    HPM_RESET_HOLD_TIME=0 \
    HPM_BOOT_WAIT_TIME=0 \
    HPM_TEST_LOG="$tmpdir/hpmtool.log" \
    HPM_TEST_WRITE_STATUS="${1:-0}" \
        scripts/flash_hpm.sh "$tmpdir/firmware.bin"
}

run_flash
mapfile -t calls < "$tmpdir/hpmtool.log"
[[ "${calls[0]}" == '-u -c hpm5e00 erase_flash' ]]
[[ "${calls[1]}" == "-u -c hpm5e00 write_flash 0x400 $tmpdir/firmware.bin" ]]
[[ "$(cat "$tmpdir/hpm-boot")" == 0 ]]
[[ "$(cat "$tmpdir/hpm-reset")" == 1 ]]

printf '1\n' > "$tmpdir/hpm-boot"
printf '0\n' > "$tmpdir/hpm-reset"
if run_flash 1; then
    echo 'flash unexpectedly succeeded' >&2
    exit 1
fi
[[ "$(cat "$tmpdir/hpm-boot")" == 0 ]]
[[ "$(cat "$tmpdir/hpm-reset")" == 1 ]]

echo 'PASS: HPM flash sequence and failure recovery'
