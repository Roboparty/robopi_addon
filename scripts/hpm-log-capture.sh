#!/bin/sh
set -eu

device=${HPM_LOG_DEVICE:-/dev/ttyS4}
baud=${HPM_LOG_BAUD:-115200}

case $baud in
    ''|*[!0-9]*) echo "hpm-log-capture: invalid baud rate: $baud" >&2; exit 1 ;;
esac

while [ ! -c "$device" ]; do
    echo "hpm-log-capture: waiting for $device" >&2
    sleep 5
done

stty -F "$device" "$baud" raw -echo -ixon -ixoff -crtscts
echo "hpm-log-capture: recording $device at $baud baud" >&2
exec cat "$device"
