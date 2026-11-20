#!/usr/bin/env bash
# Run a freshly built adb *inside* an Android emulator and let it debug that
# same emulator over TCP (127.0.0.1:5555), which is what Wi-Fi self-debugging
# on a phone looks like after `adb connect`.
#
# Usage: smoke-test.sh <adb-binary>
#
# Needs a running emulator reachable by the host's adb. adbd on an emulator
# already listens on tcp:5555, and it trusts the host's adb key, so the adb
# under test borrows that key to skip the authorization dialog.
set -euo pipefail

if [ $# -ne 1 ]; then
	echo "usage: $0 <adb-binary>" >&2
	exit 2
fi

BIN=$1
D=/data/local/tmp/adb-smoke
SERVER_PORT=5038 # adb server of the binary under test (the host's uses 5037)
TARGET=127.0.0.1:5555

# Keep a copy of the output; on failure in GitHub Actions, put its tail into
# an annotation so it is readable without opening the job log.
LOG=$(mktemp)
exec > >(tee "$LOG") 2>&1
report() {
	local status=$?
	if [ "$status" -ne 0 ] && [ -n "${GITHUB_ACTIONS:-}" ]; then
		local tail_
		tail_=$(tail -n 60 "$LOG" | tr -d '\r')
		tail_=${tail_//%/%25}
		local level=error
		if [ -n "${SMOKE_OPTIONAL:-}" ]; then level=warning; fi
		echo "::$level title=smoke test failed ($BIN)::${tail_//$'\n'/%0A}"
	fi
	rm -f "$LOG"
}
trap report EXIT

step() { printf '\n==> %s\n' "$*"; }

# Run the adb under test on the device.
dadb() {
	adb shell "cd $D && HOME=$D TMPDIR=$D/tmp ./adb -P $SERVER_PORT $*"
}

step "Waiting for the emulator"
adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 1; done'
adb shell getprop ro.product.cpu.abilist

step "Installing $BIN"
adb shell "rm -rf $D && mkdir -p $D/.android $D/tmp"
adb push "$BIN" "$D/adb" >/dev/null
adb shell chmod 755 "$D/adb"
adb push "$HOME/.android/adbkey" "$D/.android/adbkey" >/dev/null

step "adb version"
dadb version

step "adb start-server"
dadb start-server

connect() {
	local out
	out=$(dadb connect "$TARGET" | tr -d '\r')
	echo "$out"
	case $out in
	*"connected to"*) return 0 ;;
	*) return 1 ;;
	esac
}

step "adb connect $TARGET"
if ! connect; then
	# Some images only expose adbd over vsock; make it listen on TCP too.
	echo "adbd is not on tcp:5555, switching it with 'adb tcpip 5555'"
	adb tcpip 5555 || true
	sleep 5
	adb wait-for-device
	if ! connect; then
		echo "error: connect failed" >&2
		adb shell "cat $D/tmp/adb.*.log" || true
		exit 1
	fi
fi

step "adb devices -l"
dadb wait-for-device
dadb devices -l

step "adb shell through the connection"
reply=$(dadb -s "$TARGET" shell echo self-debug-ok | tr -d '\r')
echo "$reply"
test "$reply" = self-debug-ok
dadb -s "$TARGET" shell id
dadb -s "$TARGET" shell getprop ro.build.version.release

step "adb push / pull through the connection"
adb shell "echo payload-123 > $D/tmp/src.txt"
dadb -s "$TARGET" push "$D/tmp/src.txt" /data/local/tmp/adb-smoke-copy.txt
test "$(adb shell cat /data/local/tmp/adb-smoke-copy.txt | tr -d '\r')" = payload-123
adb shell rm -f /data/local/tmp/adb-smoke-copy.txt

step "adb kill-server"
dadb kill-server

echo
echo "smoke test passed"
