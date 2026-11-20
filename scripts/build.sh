#!/usr/bin/env bash
# Build adb locally (Linux x86_64 host), the same way CI does.
#
# Usage: scripts/build.sh [aosp-ref]
#
#   aosp-ref  defaults to the newest android-X.Y.Z_rN tag of AOSP adb
#
# Output goes to ./dist; intermediate files to ./work.
# Needs: git, curl, cmake (>= 3.20), ninja, patch, unzip, zip, a host C/C++
# compiler. Set ANDROID_NDK_HOME to reuse an NDK, otherwise it is downloaded.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$ROOT/work
DIST=$ROOT/dist

ref=${1:-}
if [ -z "$ref" ]; then
	ref=$(FORCE=true bash "$ROOT/scripts/check-update.sh" | sed -n 's/^tag=//p')
fi

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
	eval "export $(bash "$ROOT/scripts/setup-ndk.sh" "$WORK/ndk")"
fi

bash "$ROOT/scripts/fetch-sources.sh" "$ref" "$WORK"
bash "$ROOT/scripts/build-deps.sh" "$WORK"
bash "$ROOT/scripts/build-adb.sh" "$WORK" "$DIST"
