#!/usr/bin/env bash
# Fixture harness for scripts/commit-msg.sh
# Run: bash scripts/commit-msg-test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/commit-msg.sh"
TMPDIR_="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_"' EXIT

PASS=0
FAIL=0

echo "🪡 commit-msg validator tests"

# expect <accept|reject> <name> <message...>
expect() {
  local want="$1" name="$2"; shift 2
  local file="$TMPDIR_/msg"
  printf '%s\n' "$@" > "$file"

  local out rc
  out=$(bash "$HOOK" "$file" 2>&1); rc=$?

  local got="accept"
  [[ $rc -ne 0 ]] && got="reject"

  printf "  %-8s %-46s" "$want" "$name"
  if [[ "$got" == "$want" ]]; then
    echo "✓"
    PASS=$((PASS+1))
  else
    echo "✗ FAILED (exit $rc, wanted $want)"
    echo "$out" | sed 's/^/      /'
    FAIL=$((FAIL+1))
  fi
}

long_subject="feat: $(printf 'x%.0s' {1..80})"
max_subject="feat: $(printf 'x%.0s' {1..66})"   # exactly 72 chars
over_subject="feat: $(printf 'x%.0s' {1..67})"  # exactly 73 chars

# --- accepted ---
expect accept "plain type"              "feat: add budget calibration"
expect accept "scoped"                  "fix(config): guard nil provider map"
expect accept "breaking scoped"         "feat(api)!: drop legacy budget fields"
expect accept "breaking unscoped"       "feat!: require go 1.23"
expect accept "single-char subject"     "feat: x"
expect accept "nested scope"            "docs(website/docs): clarify install"
expect accept "subject exactly 72"      "$max_subject"
expect accept "body after blank line"   "fix: correct day boundary" "" "The daily window rolled over in UTC instead of local time."
expect accept "trailers"                "chore: normalize commit messages" "" "Nightshift-Task: commit-normalize" "Nightshift-Ref: https://github.com/marcus/nightshift"
expect accept "breaking change footer"  "feat: drop v1 config" "" "BREAKING CHANGE: config.v1 keys are no longer read."
expect accept "merge commit"            "Merge pull request #17 from cedricfarinazzo/nightshift-lint-fixes"
expect accept "revert commit"           "Revert \"feat: add budget calibration\"" "" "This reverts commit deadbeef."
expect accept "fixup!"                  "fixup! feat: add budget calibration"
expect accept "squash!"                 "squash! feat: add budget calibration"
expect accept "amend!"                  "amend! feat: add budget calibration"
expect accept "comments stripped"       "# please enter the commit message" "feat: add doctor command" "# Changes to be committed:"
expect accept "commit -v diff ignored"  "fix: drop stale lock file" "" "# ------------------------ >8 ------------------------" "diff --git a/x.go b/x.go" "+FEAT: NOT A SUBJECT."
expect accept "empty message"           "" "# nothing staged"
expect accept "all allowed types"       "perf: hoist regex out of loop"
expect accept "ci type"                 "ci: lint pull request commit messages"
expect accept "revert type prefix"      "revert: feat add budget calibration"

# --- rejected ---
expect reject "unknown type"            "foo: add a thing"
expect reject "missing colon"           "add budget calibration"
expect reject "capitalized subject"     "feat: Add budget calibration"
expect reject "trailing period"         "feat: add budget calibration."
expect reject "subject over 72"         "$over_subject"
expect reject "very long subject"       "$long_subject"
expect reject "empty subject text"      "feat:"
expect reject "no space after colon"    "feat:add budget calibration"
expect reject "uppercase type"          "Feat: add budget calibration"
expect reject "uppercase scope"         "fix(Config): guard nil provider map"
expect reject "empty scope"             "fix(): guard nil provider map"
expect reject "body without blank line" "fix: correct day boundary" "The window rolled over in UTC."
expect reject "leading whitespace"      "  feat: add budget calibration"
expect reject "subject is only spaces"  "   "

echo ""
if [[ $FAIL -gt 0 ]]; then
  echo "❌ $FAIL of $((PASS+FAIL)) test(s) failed"
  exit 1
fi
echo "✅ All $PASS tests passed"
