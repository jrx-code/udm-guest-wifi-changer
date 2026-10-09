#!/bin/bash
# Tests for the WLAN JSON helpers in change_guest_pass.sh (no network, no UDM).
# Run: bash tests/test_ssid_lookup.sh
set -u
cd "$(dirname "$0")/.." || exit 1

# Load only the helper functions, not the main part of the script.
eval "$(sed -n -e '/^find_ssid_id() {/,/^}/p' -e '/^list_ssid_names() {/,/^}/p' change_guest_pass.sh)"

FIXTURE=tests/wlanconf_sample.json
# Same data as the UDM returns it: one line, no spaces.
COMPACT=$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), separators=(",", ":")))' "$FIXTURE")
FAILED=0

check() {
    if [ "$2" = "$3" ]; then
        echo "ok   - $1"
    else
        echo "FAIL - $1: expected '$3', got '$2'"
        FAILED=1
    fi
}

for body in "$(cat "$FIXTURE")" "$COMPACT"; do
    check "first network" "$(printf '%s' "$body" | find_ssid_id "Example-Guest")" "0000aaaa1111bbbb2222cc01"
    check "middle network" "$(printf '%s' "$body" | find_ssid_id "Example-Home")" "0000aaaa1111bbbb2222cc02"
    check "last network, name with space" "$(printf '%s' "$body" | find_ssid_id "Example-Guest IoT")" "0000aaaa1111bbbb2222cc03"
    check "unknown name" "$(printf '%s' "$body" | find_ssid_id "Nope")" ""
    check "no partial match" "$(printf '%s' "$body" | find_ssid_id "Example")" ""
    check "list names" "$(printf '%s' "$body" | list_ssid_names | tr '\n' '|')" "Example-Guest|Example-Home|Example-Guest IoT|"
done

check "bare array" "$(printf '%s' '[{"_id":"x1","name":"A"},{"_id":"x2","name":"B"}]' | find_ssid_id "A")" "x1"
check "invalid JSON" "$(printf '%s' 'not json' | find_ssid_id "A")" ""

exit $FAILED
