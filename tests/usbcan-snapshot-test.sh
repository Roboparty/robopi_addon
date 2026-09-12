#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/bin" "$tmpdir/capture" "$tmpdir/snapshots"
printf 'pcap-data\n' > "$tmpdir/capture/usbcan.pcap0"

cat > "$tmpdir/bin/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl:%s\n' "$*" >> "$USBCAN_TEST_LOG"
case $1 in
    is-active) exit 0 ;;
    stop|start) exit 0 ;;
    *) exit 1 ;;
esac
EOF
for command_name in lsusb ip journalctl dmesg; do
    cat > "$tmpdir/bin/$command_name" <<EOF
#!/bin/sh
printf '$command_name:%s\n' "\$*"
EOF
done
chmod +x "$tmpdir/bin"/*

output=$(
    PATH="$tmpdir/bin:/usr/bin:/bin" \
    USBCAN_ALLOW_NON_ROOT=yes \
    USBCAN_CAPTURE_DIR="$tmpdir/capture" \
    USBCAN_SNAPSHOT_DIR="$tmpdir/snapshots" \
    USBCAN_SNAPSHOT_LOCK="$tmpdir/snapshot.lock" \
    USBCAN_TEST_LOG="$tmpdir/systemctl.log" \
    scripts/usbcan-debug-snapshot.sh
)

[[ -f "$output/usbcan.pcap0" ]]
cmp "$tmpdir/capture/usbcan.pcap0" "$output/usbcan.pcap0"
[[ -f "$output/lsusb.txt" && -f "$output/dmesg.txt" ]]
[[ -f "$output/hpm-uart-journal.txt" ]]
grep -q '^journalctl:-u hpm-log-capture.service -b --no-pager$' \
    "$output/hpm-uart-journal.txt"
grep -q '^systemctl:stop usbcan-capture.service$' "$tmpdir/systemctl.log"
grep -q '^systemctl:start usbcan-capture.service$' "$tmpdir/systemctl.log"

echo 'PASS: snapshot copies capture and diagnostics, then restarts active service'

# A failed copy must remove the partial snapshot and restart capture.
mkdir -p "$tmpdir/fail-snapshots"
cat > "$tmpdir/bin/cp" <<'EOF'
#!/bin/sh
for destination do :; done
printf 'partial\n' > "$destination/usbcan.pcap0"
exit 1
EOF
chmod +x "$tmpdir/bin/cp"

if PATH="$tmpdir/bin:/usr/bin:/bin" \
    USBCAN_ALLOW_NON_ROOT=yes \
    USBCAN_CAPTURE_DIR="$tmpdir/capture" \
    USBCAN_SNAPSHOT_DIR="$tmpdir/fail-snapshots" \
    USBCAN_SNAPSHOT_LOCK="$tmpdir/fail-snapshot.lock" \
    USBCAN_TEST_LOG="$tmpdir/fail-systemctl.log" \
    scripts/usbcan-debug-snapshot.sh; then
    echo 'snapshot unexpectedly succeeded with failing cp' >&2
    exit 1
fi

[[ -z "$(find "$tmpdir/fail-snapshots" -mindepth 1 -maxdepth 1 -print -quit)" ]]
grep -q '^systemctl:stop usbcan-capture.service$' "$tmpdir/fail-systemctl.log"
grep -q '^systemctl:start usbcan-capture.service$' "$tmpdir/fail-systemctl.log"

echo 'PASS: failed copy removes partial snapshot and restarts active service'

# Insufficient target space must be rejected before capture is stopped.
rm "$tmpdir/bin/cp"
cat > "$tmpdir/bin/df" <<'EOF'
#!/bin/sh
cat <<'OUTPUT'
Filesystem 1024-blocks Used Available Capacity Mounted on
testfs 100 99 1 99% /test
OUTPUT
EOF
chmod +x "$tmpdir/bin/df"
mkdir -p "$tmpdir/full-snapshots"

if PATH="$tmpdir/bin:/usr/bin:/bin" \
    USBCAN_ALLOW_NON_ROOT=yes \
    USBCAN_CAPTURE_DIR="$tmpdir/capture" \
    USBCAN_SNAPSHOT_DIR="$tmpdir/full-snapshots" \
    USBCAN_SNAPSHOT_LOCK="$tmpdir/full-snapshot.lock" \
    USBCAN_TEST_LOG="$tmpdir/full-systemctl.log" \
    scripts/usbcan-debug-snapshot.sh; then
    echo 'snapshot unexpectedly succeeded without enough target space' >&2
    exit 1
fi

[[ ! -e "$tmpdir/full-systemctl.log" ]]
[[ -z "$(find "$tmpdir/full-snapshots" -mindepth 1 -maxdepth 1 -print -quit)" ]]

echo 'PASS: insufficient space is rejected before capture is stopped'
