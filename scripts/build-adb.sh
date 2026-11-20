#!/usr/bin/env bash
# Configure, build and package adb.
#
# Usage: build-adb.sh <work-dir> <dist-dir>
#
# Expects fetch-sources.sh and build-deps.sh to have run on <work-dir>.
#
# Environment:
#   ANDROID_NDK_HOME  path to the Android NDK (required)
set -euo pipefail

if [ $# -ne 2 ]; then
	echo "usage: $0 <work-dir> <dist-dir>" >&2
	exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(cd "$1" && pwd)
DIST=$(mkdir -p "$2" && cd "$2" && pwd)
# shellcheck source=versions.env
source "$ROOT/scripts/versions.env"
# shellcheck disable=SC1091
source "$WORK/source-info.env"
: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to the Android NDK}"

BLD=$WORK/adb-build
PREFIX=$WORK/prefix
LLVM=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin

echo "==> Configuring adb ($AOSP_REF, platform-tools $PLATFORM_TOOLS_VERSION)"
rm -rf "$BLD"
cmake -S "$WORK/vendor" -B "$BLD" -G Ninja \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
	-DANDROID_ABI="$ANDROID_ABI" \
	-DANDROID_PLATFORM="android-$ANDROID_API" \
	-DANDROID_STL=c++_static \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	-DDEPS_PREFIX="$PREFIX" \
	-DProtobuf_PROTOC_EXECUTABLE="$WORK/host/bin/protoc" \
	-DProtobuf_INCLUDE_DIR="$PREFIX/include" \
	-DProtobuf_LIBRARY="$PREFIX/lib/libprotobuf.a" \
	-DPLATFORM_TOOLS_VERSION="$PLATFORM_TOOLS_VERSION" \
	-DADB_BUILD_ID="$AOSP_REF"

echo "==> Building adb"
# Keep the full log, and turn compiler errors into GitHub annotations so
# they show up on the run summary page.
set +e
cmake --build "$BLD" --target adb 2>&1 | tee "$WORK/adb-build.log"
status=${PIPESTATUS[0]}
set -e
if [ "$status" -ne 0 ]; then
	if [ -n "${GITHUB_ACTIONS:-}" ]; then
		grep -E 'error:|undefined (symbol|reference)|FAILED:' "$WORK/adb-build.log" | head -n 40 |
			sed 's/^/::error::/' || true
	fi
	exit "$status"
fi

echo "==> Packaging"
"$LLVM/llvm-strip" --strip-unneeded -o "$DIST/adb" "$BLD/adb"
chmod 755 "$DIST/adb"

echo "--- ELF header"
"$LLVM/llvm-readelf" -h "$DIST/adb" | grep -E 'Class|Machine|Type'
echo "--- Dynamic dependencies"
needed=$("$LLVM/llvm-readelf" -d "$DIST/adb" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')
echo "$needed"
# Only libraries that every Android device ships are allowed.
for lib in $needed; do
	case $lib in
	libc.so | libm.so | libdl.so | libz.so | liblog.so) ;;
	*)
		echo "error: unexpected dependency $lib" >&2
		exit 1
		;;
	esac
done

# License texts of everything linked into the binary.
lic=$WORK/licenses
rm -rf "$lic"
mkdir -p "$lic"
copy_license() {
	if [ -f "$2" ]; then cp "$2" "$lic/$1"; else echo "warning: missing license $2" >&2; fi
}
copy_license adb.NOTICE "$WORK/vendor/adb/NOTICE"
copy_license libbase.NOTICE "$WORK/vendor/libbase/NOTICE"
copy_license core.NOTICE "$WORK/vendor/core/NOTICE"
copy_license logging.NOTICE "$WORK/vendor/logging/NOTICE"
copy_license libziparchive.NOTICE "$WORK/vendor/libziparchive/NOTICE"
copy_license boringssl.LICENSE "$WORK/vendor/boringssl/LICENSE"
copy_license fmtlib.LICENSE "$WORK/vendor/fmtlib/LICENSE"
copy_license libusb.COPYING "$WORK/vendor/libusb/COPYING"
copy_license protobuf.LICENSE "$WORK/deps-src/protobuf/LICENSE"
copy_license brotli.LICENSE "$WORK/deps-src/brotli/LICENSE"
copy_license lz4.LICENSE "$WORK/deps-src/lz4/lib/LICENSE"
copy_license zstd.LICENSE "$WORK/deps-src/zstd/LICENSE"

pkg=adb-$ANDROID_ABI
rm -rf "${WORK:?}/$pkg" "$DIST/$pkg.zip"
mkdir -p "$WORK/$pkg"
cp "$DIST/adb" "$WORK/$pkg/"
cp -r "$lic" "$WORK/$pkg/licenses"
cat >"$WORK/$pkg/BUILD-INFO.txt" <<EOF
adb $PLATFORM_TOOLS_VERSION for Android $ANDROID_ABI (API $ANDROID_API+)
AOSP ref:     $AOSP_REF
adb commit:   $ADB_COMMIT
recipe:       nmeum/android-tools@$RECIPE_COMMIT
NDK:          $NDK_VERSION
protobuf:     $PROTOBUF_VERSION
brotli:       $BROTLI_VERSION
lz4:          $LZ4_VERSION
zstd:         $ZSTD_VERSION
EOF
(cd "$WORK" && zip -qr "$DIST/$pkg.zip" "$pkg")
(cd "$DIST" && sha256sum adb "$pkg.zip" >SHA256SUMS)
cp "$WORK/$pkg/BUILD-INFO.txt" "$DIST/"

echo "==> Output in $DIST"
ls -l "$DIST"
cat "$DIST/SHA256SUMS"
