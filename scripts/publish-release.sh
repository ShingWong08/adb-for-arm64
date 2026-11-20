#!/usr/bin/env bash
# Create (or update) the GitHub release for a finished build.
#
# Usage: publish-release.sh <dist-dir>
#
#   dist-dir  output of build-adb.sh (adb, adb-<abi>.zip, SHA256SUMS,
#             source-info.env)
#
# Environment:
#   GH_TOKEN  token with contents:write (provided by GitHub Actions)
#   GH_REPO   owner/repo (defaults to the git remote)
set -euo pipefail

if [ $# -ne 1 ]; then
	echo "usage: $0 <dist-dir>" >&2
	exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIST=$(cd "$1" && pwd)
# shellcheck source=versions.env
source "$ROOT/scripts/versions.env"
# shellcheck disable=SC1091
source "$DIST/source-info.env"

tag=$AOSP_REF
title="adb $PLATFORM_TOOLS_VERSION ($AOSP_REF)"
assets=("$DIST/adb" "$DIST/adb-$ANDROID_ABI.zip" "$DIST/SHA256SUMS")
adb_url=https://android.googlesource.com/platform/packages/modules/adb
repo=${GH_REPO:-${GITHUB_REPOSITORY:-}}

notes=$(mktemp)
cat >"$notes" <<EOF
從 AOSP \`$AOSP_REF\` 編譯的 adb，可以直接在 **Android $ANDROID_ABI** 手機上執行（Android 7.0 / API $ANDROID_API 或以上）。

| | |
|---|---|
| platform-tools 版本 | $PLATFORM_TOOLS_VERSION |
| AOSP 標籤 | [\`$AOSP_REF\`]($adb_url/+/refs/tags/$AOSP_REF) |
| adb commit | [\`${ADB_COMMIT:0:12}\`]($adb_url/+/$ADB_COMMIT) |
| 編譯配方 | [nmeum/android-tools@${RECIPE_COMMIT:0:12}](https://github.com/nmeum/android-tools/commit/$RECIPE_COMMIT) |
| NDK | $NDK_VERSION |

**檔案**
- \`adb\`：執行檔本體
- \`adb-$ANDROID_ABI.zip\`：執行檔 + 授權條款 + 編譯資訊
- \`SHA256SUMS\`：校驗碼

用法（例如 Wi-Fi 自我調試）請看 [README](https://github.com/$repo#readme)。

\`\`\`
$(cat "$DIST/SHA256SUMS")
\`\`\`
EOF

if gh release view "$tag" >/dev/null 2>&1; then
	echo "Updating existing release $tag"
	gh release upload "$tag" "${assets[@]}" --clobber
	gh release edit "$tag" --title "$title" --notes-file "$notes"
else
	echo "Creating release $tag"
	gh release create "$tag" "${assets[@]}" \
		--title "$title" \
		--notes-file "$notes" \
		--target "${GITHUB_SHA:-$(git -C "$ROOT" rev-parse HEAD)}"
fi
rm -f "$notes"
