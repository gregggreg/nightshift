#!/bin/sh
# Validate every commit in a range against the nightshift commit convention.
#
# Usage: scripts/check-commit-range.sh [--base <ref>] [<head>]
#
# Validates <base>..<head>, defaulting to origin/main..HEAD. Used by the
# commit-lint CI job so pull request commits are checked without touching
# historical commits already on the default branch.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
validator="$script_dir/commit-msg.sh"

base="origin/main"
head="HEAD"

while [ "$#" -gt 0 ]; do
	case "$1" in
	--base)
		if [ "$#" -lt 2 ]; then
			echo "check-commit-range: --base requires a value" >&2
			exit 2
		fi
		base=$2
		shift 2
		;;
	--base=*)
		base=${1#--base=}
		shift
		;;
	-h | --help)
		echo "usage: $0 [--base <ref>] [<head>]"
		exit 0
		;;
	-*)
		echo "check-commit-range: unknown option: $1" >&2
		exit 2
		;;
	*)
		head=$1
		shift
		;;
	esac
done

if [ ! -x "$validator" ]; then
	echo "check-commit-range: validator not executable: $validator" >&2
	exit 2
fi

# Only inspect commits unique to <head>; anything reachable from <base> is
# existing history and deliberately left alone.
revs=$(git rev-list --no-merges "$base".."$head")

if [ -z "$revs" ]; then
	echo "✓ no commits to check in $base..$head"
	exit 0
fi

tmp_file=$(mktemp "${TMPDIR:-/tmp}/nightshift-commit-range.XXXXXX")
cleanup() { rm -f "$tmp_file"; }
trap cleanup EXIT HUP INT TERM

checked=0
failed=0

for rev in $revs; do
	checked=$((checked + 1))
	git log -1 --format=%B "$rev" >"$tmp_file"
	if ! "$validator" "$tmp_file"; then
		echo "  ↳ commit $(git log -1 --format='%h' "$rev")" >&2
		echo "" >&2
		failed=$((failed + 1))
	fi
done

if [ "$failed" -gt 0 ]; then
	echo "✗ $failed of $checked commit(s) do not follow the commit convention" >&2
	echo "  see docs/guides/commit-messages.md" >&2
	exit 1
fi

echo "✓ all $checked commit(s) follow the commit convention"
