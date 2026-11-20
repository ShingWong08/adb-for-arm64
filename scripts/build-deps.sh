#!/usr/bin/env bash
# Build the third-party libraries adb links against.
#
# Usage: build-deps.sh <work-dir>
#
# Environment:
#   ANDROID_NDK_HOME  path to the Android NDK (required)
#
# Produces:
#   <work-dir>/host/bin/protoc   protobuf compiler for the build machine
#   <work-dir>/prefix/           static Android libraries + headers
set -euo pipefail

if [ $# -ne 1 ]; then
	echo "usage: $0 <work-dir>" >&2
	exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
# shellcheck source=versions.env
source "$ROOT/scripts/versions.env"
: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to the Android NDK}"

DL=$WORK/downloads
SRC=$WORK/deps-src
BLD=$WORK/deps-build
HOST=$WORK/host
PREFIX=$WORK/prefix
mkdir -p "$DL" "$SRC" "$BLD"

COMMON=(
	-G Ninja
	-DCMAKE_BUILD_TYPE=Release
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5
	-DBUILD_SHARED_LIBS=OFF
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON
	-DCMAKE_INSTALL_LIBDIR=lib
)
ANDROID=(
	-DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
	-DANDROID_ABI="$ANDROID_ABI"
	-DANDROID_PLATFORM="android-$ANDROID_API"
	-DANDROID_STL=c++_static
	-DCMAKE_INSTALL_PREFIX="$PREFIX"
)

# fetch <name> <url> <sha256>: download and unpack into $SRC/<name>
fetch() {
	local name=$1 url=$2 sha=$3 file=$DL/$1.tar.gz
	if [ ! -f "$file" ] || ! echo "$sha  $file" | sha256sum -c --status -; then
		curl -fsSL --retry 3 -o "$file" "$url"
		echo "$sha  $file" | sha256sum -c -
	fi
	rm -rf "${SRC:?}/$name"
	mkdir -p "$SRC/$name"
	tar -xzf "$file" -C "$SRC/$name" --strip-components=1
}

# build <name> <source-dir> [cmake args...]
build() {
	local name=$1 src=$2
	shift 2
	echo "==> $name"
	rm -rf "${BLD:?}/$name"
	cmake -S "$src" -B "$BLD/$name" "${COMMON[@]}" "$@" >"$BLD/$name.configure.log" ||
		{ cat "$BLD/$name.configure.log"; return 1; }
	cmake --build "$BLD/$name"
	cmake --install "$BLD/$name" >/dev/null
}

fetch protobuf "$PROTOBUF_URL" "$PROTOBUF_SHA256"
fetch brotli "$BROTLI_URL" "$BROTLI_SHA256"
fetch lz4 "$LZ4_URL" "$LZ4_SHA256"
fetch zstd "$ZSTD_URL" "$ZSTD_SHA256"

build protoc-host "$SRC/protobuf" \
	-DCMAKE_INSTALL_PREFIX="$HOST" \
	-Dprotobuf_BUILD_TESTS=OFF \
	-Dprotobuf_BUILD_SHARED_LIBS=OFF \
	-Dprotobuf_WITH_ZLIB=OFF

build protobuf "$SRC/protobuf" "${ANDROID[@]}" \
	-Dprotobuf_BUILD_TESTS=OFF \
	-Dprotobuf_BUILD_PROTOC_BINARIES=OFF \
	-Dprotobuf_BUILD_SHARED_LIBS=OFF \
	-Dprotobuf_WITH_ZLIB=OFF

build brotli "$SRC/brotli" "${ANDROID[@]}" \
	-DBROTLI_DISABLE_TESTS=ON

build lz4 "$SRC/lz4/build/cmake" "${ANDROID[@]}" \
	-DBUILD_STATIC_LIBS=ON \
	-DLZ4_BUILD_CLI=OFF \
	-DLZ4_BUILD_LEGACY_LZ4C=OFF

build zstd "$SRC/zstd/build/cmake" "${ANDROID[@]}" \
	-DZSTD_BUILD_STATIC=ON \
	-DZSTD_BUILD_SHARED=OFF \
	-DZSTD_BUILD_PROGRAMS=OFF \
	-DZSTD_BUILD_TESTS=OFF \
	-DZSTD_LEGACY_SUPPORT=OFF

"$HOST/bin/protoc" --version
ls -l "$PREFIX/lib"
