#!/bin/sh
# Table tests for scripts/commit-msg.sh.
#
# Usage: make test-scripts  (or: ./scripts/commit-msg_test.sh)
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
validator="$script_dir/commit-msg.sh"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/nightshift-commit-msg-test.XXXXXX")
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT HUP INT TERM

pass=0
fail=0

# check <expected-exit> <name> <message>
check() {
	expected=$1
	name=$2
	message=$3

	file="$tmp_dir/msg"
	printf '%s\n' "$message" >"$file"

	set +e
	output=$("$validator" "$file" 2>&1)
	actual=$?
	set -e

	if [ "$actual" -eq "$expected" ]; then
		pass=$((pass + 1))
		printf '  ✓ %s\n' "$name"
	else
		fail=$((fail + 1))
		printf '  ✗ %s (want exit %s, got %s)\n' "$name" "$expected" "$actual"
		printf '%s\n' "$output" | sed 's/^/      /'
	fi
}

echo "commit-msg validator"

# --- accepted: one per allowed type ---
for type in feat fix docs refactor test chore build ci perf style revert; do
	check 0 "accepts type $type" "$type: add a thing"
done

# --- accepted: shapes ---
check 0 "accepts scope" "feat(orchestrator): add plan retry"
check 0 "accepts scope with slash" "fix(internal/tasks): guard nil task"
check 0 "accepts issue-style scope" "fix(#19): honor max_projects"
check 0 "accepts breaking-change marker" "feat(config)!: drop legacy provider keys"
check 0 "accepts acronym subject" "fix: JSONL parsing reads nested usage"
check 0 "accepts subject at 72 chars" "feat: $(printf 'a%.0s' $(seq 1 66))"
check 0 "accepts body after blank line" "feat: add thing

Explains why the thing was added."
check 0 "accepts breaking-change footer" "feat(api)!: rename budget field

BREAKING CHANGE: budget.daily is now budget.per_day."
check 0 "accepts issue reference" "fix: correct budget rounding

fixes #21"
check 0 "accepts nightshift trailers" "docs: standardize commit message format

Nightshift-Task: commit-normalize
Nightshift-Ref: https://github.com/marcus/nightshift"
check 0 "accepts long URL in body" "docs: add reference

https://example.com/$(printf 'a%.0s' $(seq 1 120))"

# --- accepted: git-authored subjects pass through ---
check 0 "passes through merge commit" "Merge pull request #17 from user/branch"
check 0 "passes through revert commit" "Revert \"feat: add thing\""
check 0 "passes through fixup" "fixup! feat: add thing"
check 0 "passes through squash" "squash! feat: add thing"

# --- accepted: comments are stripped ---
check 0 "ignores comment lines" "feat: add thing
# Please enter the commit message for your changes."

# --- rejected ---
check 1 "rejects unknown type" "feature: add thing"
check 1 "rejects missing colon" "feat add thing"
check 1 "rejects bare type without subject" "fix(task)"
check 1 "rejects capitalized subject" "feat: Add thing"
check 1 "rejects non-conventional capitalized subject" "Bump version to v0.3.4"
check 1 "rejects trailing period" "feat: add thing."
check 1 "rejects over-length subject" "feat: $(printf 'a%.0s' $(seq 1 100))"
check 1 "rejects missing blank line before body" "feat: add thing
body starts immediately"
check 1 "rejects empty message" ""
check 1 "rejects comment-only message" "# nothing here"
check 1 "rejects over-length body line" "feat: add thing

$(printf 'word %.0s' $(seq 1 40))"

# --- usage errors ---
set +e
"$validator" >/dev/null 2>&1
usage_status=$?
"$validator" "$tmp_dir/does-not-exist" >/dev/null 2>&1
missing_status=$?
set -e
if [ "$usage_status" -eq 2 ]; then
	pass=$((pass + 1)); printf '  ✓ %s\n' "exits 2 without arguments"
else
	fail=$((fail + 1)); printf '  ✗ %s (want 2, got %s)\n' "exits 2 without arguments" "$usage_status"
fi
if [ "$missing_status" -eq 2 ]; then
	pass=$((pass + 1)); printf '  ✓ %s\n' "exits 2 on missing file"
else
	fail=$((fail + 1)); printf '  ✗ %s (want 2, got %s)\n' "exits 2 on missing file" "$missing_status"
fi

echo ""
if [ "$fail" -gt 0 ]; then
	echo "❌ $fail failed, $pass passed"
	exit 1
fi
echo "✅ all $pass checks passed"
