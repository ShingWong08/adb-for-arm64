#!/usr/bin/env bash
# Download the pinned Android NDK (see versions.env) unless it is already there.
#
# Usage: setup-ndk.sh <install-dir>
#
# Prints "ANDROID_NDK_HOME=<path>" on stdout, so it can be appended to
# $GITHUB_ENV or eval'ed.
set -euo pipefail

if [ $# -ne 1 ]; then
	echo "usage: $0 <install-dir>" >&2
	exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=versions.env
source "$ROOT/scripts/versions.env"

DEST=$(mkdir -p "$1" && cd "$1" && pwd)
NDK=$DEST/android-ndk-$NDK_VERSION

if [ ! -f "$NDK/build/cmake/android.toolchain.cmake" ]; then
	echo "Downloading Android NDK $NDK_VERSION" >&2
	zip=$DEST/android-ndk-$NDK_VERSION-linux.zip
	curl -fsSL --retry 3 -o "$zip" \
		"https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-linux.zip"
	rm -rf "$NDK"
	unzip -q "$zip" -d "$DEST"
	rm -f "$zip"
fi

grep -m1 '^Pkg.Revision' "$NDK/source.properties" >&2
echo "ANDROID_NDK_HOME=$NDK"
