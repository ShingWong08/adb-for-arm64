#!/usr/bin/env bash
# Decide whether there is a new AOSP adb release to build.
#
# Usage: check-update.sh [aosp-ref]
#
#   aosp-ref  optional tag or branch to build instead of the latest
#             android-X.Y.Z_rN release tag.
#
# Environment:
#   FORCE=true     build even if this adb commit was already released
#   GH_TOKEN       token for `gh release list` (provided by GitHub Actions)
#
# Prints (and appends to $GITHUB_OUTPUT when set):
#   build=true|false   tag=<aosp ref>   commit=<adb commit>
set -euo pipefail

ADB_REPO=https://android.googlesource.com/platform/packages/modules/adb
REQUESTED=${1:-}
FORCE=${FORCE:-false}

output() {
	echo "$1=$2"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "$1=$2" >>"$GITHUB_OUTPUT"
	fi
}

# tag name -> commit, peeled through annotated tags
declare -A commit_of=()
while read -r sha ref; do
	name=${ref#refs/tags/}
	if [[ $name == *'^{}' ]]; then
		commit_of[${name%'^{}'}]=$sha
	elif [[ -z ${commit_of[$name]:-} ]]; then
		commit_of[$name]=$sha
	fi
done < <(git ls-remote "$ADB_REPO" 'refs/tags/android-*')

if [ -n "$REQUESTED" ]; then
	tag=$REQUESTED
	commit=${commit_of[$tag]:-}
	if [ -z "$commit" ]; then
		# a branch name, e.g. "main" or "android17-release"
		commit=$(git ls-remote "$ADB_REPO" "refs/heads/$tag" | cut -f1)
	fi
	if [ -z "$commit" ]; then
		echo "error: '$tag' is neither a tag nor a branch of $ADB_REPO" >&2
		exit 1
	fi
else
	tag=$(printf '%s\n' "${!commit_of[@]}" |
		grep -E '^android-[0-9]+\.[0-9]+\.[0-9]+_r[0-9]+$' |
		sort -V | tail -n1)
	if [ -z "$tag" ]; then
		echo "error: no android-X.Y.Z_rN tags found in $ADB_REPO" >&2
		exit 1
	fi
	commit=${commit_of[$tag]}
fi

echo "AOSP ref: $tag (adb commit $commit)"

build=true
if [ "$FORCE" != "true" ]; then
	repo_args=()
	if [ -n "${GITHUB_REPOSITORY:-}" ]; then
		repo_args=(--repo "$GITHUB_REPOSITORY")
	fi
	released=$(gh release list "${repo_args[@]}" --limit 1000 --json tagName --jq '.[].tagName')
	for r in $released; do
		if [ "$r" = "$tag" ] || [ "${commit_of[$r]:-}" = "$commit" ]; then
			echo "adb commit $commit is already released as $r, nothing to do"
			build=false
			break
		fi
	done
fi

output build "$build"
output tag "$tag"
output commit "$commit"
