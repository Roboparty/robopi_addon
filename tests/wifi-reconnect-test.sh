#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Load functions only; do not run the daemon or touch the host network.
source <(sed '/^fail_count=0/,$d' scripts/wifi-reconnect.sh)
WIFI_INTERFACE=wlxTEST
test_state='30 (disconnected)'
test_ap=no
nmcli() {
    case "$*" in
        '-g GENERAL.STATE device show wlxTEST') echo "$test_state" ;;
        '-t -f UUID,TYPE connection show') printf 'ap:802-11-wireless\nother:802-11-wireless\nvalid:802-11-wireless\n' ;;
        '-g 802-11-wireless.mode connection show uuid ap') echo ap ;;
        '-g 802-11-wireless.mode connection show uuid '*) echo infrastructure ;;
        '-g connection.autoconnect connection show uuid '*) echo yes ;;
        '-g connection.interface-name connection show uuid other') echo wlan0 ;;
        '-g connection.interface-name connection show uuid valid') echo wlxTEST ;;
        '--wait 20 connection up uuid valid ifname wlxTEST') echo TARGET_INTERFACE_OK ;;
        *) echo "Unexpected call: $*" >&2; return 1 ;;
    esac
}
iw() { [[ $test_ap == yes ]] && printf '\ttype AP\n'; }
test_state='100 (connected)'
healthy || { echo 'Connected state failed'; exit 1; }
test_state='30 (disconnected)'
test_ap=yes
healthy || { echo 'AP protection failed'; exit 1; }
test_ap=no
if healthy; then echo 'Disconnected state incorrectly healthy'; exit 1; fi
result=$(reconnect)
[[ $result == *TARGET_INTERFACE_OK* ]] || { echo 'Interface-bound reconnect failed'; exit 1; }
echo 'PASS: connected, AP protection, disconnected, profile filtering, explicit interface'
