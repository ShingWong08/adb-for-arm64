#!/usr/bin/env bash
# Fetch the AOSP sources that adb needs and prepare them for the CMake build.
#
# Usage: fetch-sources.sh <aosp-ref> <work-dir>
#
#   aosp-ref  tag or branch present in all AOSP repositories below,
#             e.g. android-17.0.0_r1
#
# Environment:
#   NMEUM_REF  commit of github.com/nmeum/android-tools to take the CMake
#              lists and portability patches from (default: picked
#              automatically, see below)
#
# Layout produced in <work-dir>:
#   vendor/          patched sources + CMakeLists.txt (the CMake project root)
#   recipe/          checkout of nmeum/android-tools
#   source-info.env  what was fetched (sourced by build-adb.sh)
set -euo pipefail

if [ $# -ne 2 ]; then
	echo "usage: $0 <aosp-ref> <work-dir>" >&2
	exit 2
fi

REF=$1
WORK=$(mkdir -p "$2" && cd "$2" && pwd)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
AOSP=https://android.googlesource.com
VENDOR=$WORK/vendor
RECIPE=$WORK/recipe

declare -A REPOS=(
	[adb]=platform/packages/modules/adb
	[boringssl]=platform/external/boringssl
	[core]=platform/system/core
	[fmtlib]=platform/external/fmtlib
	[libbase]=platform/system/libbase
	[libusb]=platform/external/libusb
	[libziparchive]=platform/system/libziparchive
	[logging]=platform/system/logging
)

clone() {
	local dest=$VENDOR/$1 url=$AOSP/$2 try
	for try in 1 2 3 4; do
		rm -rf "$dest"
		if git -c advice.detachedHead=false clone -q --depth 1 --branch "$REF" "$url" "$dest"; then
			echo "  $1: $(git -C "$dest" rev-parse HEAD)"
			return 0
		fi
		echo "  $1: clone failed (attempt $try), retrying" >&2
		sleep $((try * 15))
	done
	echo "error: could not clone $url at $REF" >&2
	return 1
}

echo "==> Cloning AOSP repositories at $REF"
rm -rf "$VENDOR"
mkdir -p "$VENDOR"
pids=()
for name in "${!REPOS[@]}"; do
	clone "$name" "${REPOS[$name]}" &
	pids+=($!)
done
for pid in "${pids[@]}"; do
	wait "$pid"
done

adb_commit=$(git -C "$VENDOR/adb" rev-parse HEAD)

# external/boringssl keeps the upstream tree in src/; use that directly.
if [ -f "$VENDOR/boringssl/src/CMakeLists.txt" ]; then
	mv "$VENDOR/boringssl" "$VENDOR/boringssl.aosp"
	mv "$VENDOR/boringssl.aosp/src" "$VENDOR/boringssl"
	rm -rf "$VENDOR/boringssl.aosp"
fi
# Don't let new compiler warnings break the build.
sed -i -E 's/(C_CXX_WARNINGS) -Werror /\1 /' "$VENDOR/boringssl/CMakeLists.txt"

# nmeum/android-tools maintains a CMake build for adb plus the patches that
# make AOSP code build outside of the Android tree. Use the newest commit of
# it that pins the same adb commit we are building; if there is none yet (a
# brand new AOSP release), fall back to its HEAD.
echo "==> Fetching nmeum/android-tools"
rm -rf "$RECIPE"
git clone -q --filter=blob:none https://github.com/nmeum/android-tools "$RECIPE"
pick=${NMEUM_REF:-}
if [ -z "$pick" ]; then
	newer=
	for c in $(git -C "$RECIPE" rev-list --first-parent HEAD -- vendor/adb); do
		if [ "$(git -C "$RECIPE" rev-parse "$c:vendor/adb")" = "$adb_commit" ]; then
			if [ -z "$newer" ]; then
				pick=HEAD
			else
				pick=$(git -C "$RECIPE" rev-parse "$newer^1")
			fi
			break
		fi
		newer=$c
	done
	if [ -z "$pick" ]; then
		echo "warning: no nmeum/android-tools commit pins adb $adb_commit yet, using its HEAD" >&2
		pick=HEAD
	fi
fi
git -C "$RECIPE" -c advice.detachedHead=false checkout -q "$pick"
recipe_commit=$(git -C "$RECIPE" rev-parse HEAD)
echo "  recipe: $recipe_commit ($(git -C "$RECIPE" log -1 --format=%s))"

echo "==> Applying nmeum/android-tools patches"
for v in adb core libbase libziparchive logging; do
	shopt -s nullglob
	patches=("$RECIPE/patches/$v"/*.patch)
	shopt -u nullglob
	if [ ${#patches[@]} -gt 0 ]; then
		echo "  $v: ${#patches[@]} patch(es)"
		git -C "$VENDOR/$v" -c user.name=adb-for-arm64 -c user.email=ci@localhost \
			am -q "${patches[@]}"
	fi
done

echo "==> Applying Android (bionic) patches"
for p in "$ROOT"/patches/*/*.patch; do
	v=$(basename "$(dirname "$p")")
	echo "  $v: $(basename "$p")"
	patch -d "$VENDOR/$v" -p1 --forward --fuzz=3 --no-backup-if-mismatch -r - -s -i "$p"
done

echo "==> Installing CMake files"
cp "$RECIPE/vendor/CMakeLists.adb.txt" \
	"$RECIPE/vendor/CMakeLists.libbase.txt" \
	"$RECIPE/vendor/CMakeLists.libusb.txt" \
	"$VENDOR/"
cp "$ROOT/cmake/CMakeLists.txt" "$VENDOR/CMakeLists.txt"

# Platform-tools version as AOSP's build would stamp it (e.g. 37.0.0).
ptv=$(curl -fsSL "$AOSP/platform/development/+/$REF/sdk/plat_tools_source.prop_template?format=TEXT" |
	base64 -d | sed -n 's/^Pkg\.Revision=//p' | tr -d '\r' || true)
if [ -z "$ptv" ]; then
	ptv=$(sed -n 's/^set(ANDROID_VERSION \([^)]*\)).*/\1/p' "$RECIPE/CMakeLists.txt")
fi

cat >"$WORK/source-info.env" <<EOF
AOSP_REF=$REF
ADB_COMMIT=$adb_commit
PLATFORM_TOOLS_VERSION=${ptv:-unknown}
RECIPE_COMMIT=$recipe_commit
EOF
echo "==> Done"
cat "$WORK/source-info.env"
