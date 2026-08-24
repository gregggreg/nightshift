#!/usr/bin/env bash
# Self-contained test runner for scripts/normalize-commit-msg.sh.
# Usage: ./scripts/test-normalize-commit-msg.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NORMALIZE="$HERE/normalize-commit-msg.sh"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

# assert_normalizes <name> <input> <expected-output>
assert_normalizes() {
  local name="$1" input="$2" want="$3" f got
  f="$TMPDIR_TEST/msg"
  printf '%s' "$input" > "$f"
  if ! "$NORMALIZE" "$f" 2>/dev/null; then
    echo "✗ $name — normalizer exited non-zero"
    FAIL=$((FAIL + 1))
    return
  fi
  got="$(cat "$f")"
  if [[ "$got" == "$want" ]]; then
    echo "✓ $name"
    PASS=$((PASS + 1))
  else
    echo "✗ $name"
    echo "    want: $(printf '%q' "$want")"
    echo "    got:  $(printf '%q' "$got")"
    FAIL=$((FAIL + 1))
  fi
}

# assert_rejects <name> <input>
assert_rejects() {
  local name="$1" input="$2" f
  f="$TMPDIR_TEST/msg"
  printf '%s' "$input" > "$f"
  if "$NORMALIZE" --check "$f" >/dev/null 2>&1; then
    echo "✗ $name — expected rejection, got success"
    FAIL=$((FAIL + 1))
  else
    echo "✓ $name"
    PASS=$((PASS + 1))
  fi
}

# assert_unchanged <name> <input> — exempt messages must pass through verbatim
assert_unchanged() {
  assert_normalizes "$1" "$2" "${2%$'\n'}"
}

echo "normalize-commit-msg tests"
echo ""

assert_normalizes "valid subject passes through unchanged" \
  $'feat(cli): add --dry-run flag\n' \
  'feat(cli): add --dry-run flag'

assert_normalizes "valid subject with body preserved" \
  $'fix(budget): clamp nightly spend\n\nThe cap was applied after the filter.\n' \
  $'fix(budget): clamp nightly spend\n\nThe cap was applied after the filter.'

assert_normalizes "trailing period stripped" \
  $'docs: update the readme.\n' \
  'docs: update the readme'

assert_normalizes "ellipsis is not treated as a trailing period" \
  $'docs: explain the flow...\n' \
  'docs: explain the flow...'

assert_normalizes "missing blank line inserted" \
  $'feat: add retries\nRetry transient provider errors.\n' \
  $'feat: add retries\n\nRetry transient provider errors.'

assert_normalizes "extra blank lines collapsed to one" \
  $'feat: add retries\n\n\n\nRetry transient errors.\n' \
  $'feat: add retries\n\nRetry transient errors.'

assert_normalizes "uppercase type lowercased" \
  $'FEAT(CLI): add a flag\n' \
  'feat(cli): add a flag'

assert_normalizes "surrounding whitespace trimmed" \
  $'\n\n   fix:    tighten the guard   \n' \
  'fix: tighten the guard'

assert_normalizes "breaking-change marker preserved" \
  $'feat(config)!: drop the legacy schema\n' \
  'feat(config)!: drop the legacy schema'

assert_normalizes "leading comment scaffolding stripped" \
  $'# Please enter the commit message for your changes.\n# On branch main\nchore: tidy up\n' \
  'chore: tidy up'

# git runs its own cleanup after the commit-msg hook, and that cleanup is
# flow-aware: it strips comments from editor-authored messages but keeps them
# for `git commit -m`. Deleting them here would destroy body text git keeps.
assert_normalizes "comment lines in the body are left for git to clean up" \
  $'chore: tidy up\n\n#note kept?\n\nNightshift-Task: t1\n' \
  $'chore: tidy up\n\n#note kept?\n\nNightshift-Task: t1'

assert_normalizes "trailing comment block left for git to clean up" \
  $'chore: tidy up\n# Please enter the commit message for your changes.\n# On branch main\n' \
  $'chore: tidy up\n\n# Please enter the commit message for your changes.\n# On branch main'

assert_normalizes "scissors section dropped" \
  $'chore: tidy up\n# ------------------------ >8 ------------------------\ndiff --git a/x b/x\n' \
  'chore: tidy up'

# --- trailers must survive byte-for-byte ------------------------------------
TRAILER_MSG=$'feat(tasks): add the normalizer.\n\nBody paragraph stays as written.\n\nNightshift-Task: commit-normalize\nNightshift-Ref: https://github.com/marcus/nightshift\nCo-Authored-By: Someone <someone@example.com>\n'
assert_normalizes "git trailers preserved byte-for-byte" \
  "$TRAILER_MSG" \
  $'feat(tasks): add the normalizer\n\nBody paragraph stays as written.\n\nNightshift-Task: commit-normalize\nNightshift-Ref: https://github.com/marcus/nightshift\nCo-Authored-By: Someone <someone@example.com>'

# --- exemptions --------------------------------------------------------------
assert_unchanged "merge commits exempt" \
  $'Merge pull request #17 from someone/branch\n'

assert_unchanged "revert commits exempt" \
  $'Revert "feat: add a thing."\n\nThis reverts commit deadbeef.\n'

assert_unchanged "fixup commits exempt" \
  $'fixup! feat: add a thing.\n'

assert_unchanged "squash commits exempt" \
  $'squash! feat: add a thing.\n'

assert_unchanged "amend commits exempt" \
  $'amend! feat: add a thing.\n'

# --- rejections --------------------------------------------------------------
assert_rejects "unknown type rejected" $'wibble: do a thing\n'
assert_rejects "free-form subject rejected" $'Add pre-commit hook for gofmt\n'
assert_rejects "empty message rejected" $'\n\n'
assert_rejects "empty description rejected" $'feat: \n'

# --- CRLF input keeps CRLF line endings --------------------------------------
assert_normalizes "crlf message keeps crlf endings" \
  $'feat: x\r\n\r\nbody\r\n' \
  $'feat: x\r\n\r\nbody\r'

assert_normalizes "crlf message with a missing separator" \
  $'Feat: X.\r\nbody\r\n' \
  $'feat: X\r\n\r\nbody\r'

# --- --check accepts only already-normalized messages ------------------------
# assert_check_ok / assert_check_fails <name> <input>
assert_check_ok() {
  local name="$1" input="$2" f
  f="$TMPDIR_TEST/chk"
  printf '%s' "$input" > "$f"
  if "$NORMALIZE" --check "$f" >/dev/null 2>&1; then
    echo "✓ $name"; PASS=$((PASS + 1))
  else
    echo "✗ $name \u2014 expected --check to pass"; FAIL=$((FAIL + 1))
  fi
}

assert_check_ok "--check accepts a normalized message" \
  $'feat(cli): add --dry-run flag\n'
assert_check_ok "--check accepts a normalized message with trailers" \
  $'feat(tasks): add the normalizer\n\nBody paragraph.\n\nNightshift-Task: commit-normalize\n'
assert_check_ok "--check exempts merge commits" \
  $'Merge pull request #17 from someone/branch\n'

assert_rejects "--check rejects an uppercase type with a trailing period" \
  $'Feat(API): Add thing.\n'
assert_rejects "--check rejects a missing blank line before the body" \
  $'feat: x\nbody line\n'
assert_rejects "--check rejects extra blank lines before the body" \
  $'feat: x\n\n\nbody line\n'
assert_rejects "--check rejects a trailing period" \
  $'docs: update the readme.\n'

# --- --check never rewrites --------------------------------------------------
CHECK_FILE="$TMPDIR_TEST/check"
printf '%s' $'docs: update the readme.\n' > "$CHECK_FILE"
"$NORMALIZE" --check "$CHECK_FILE" >/dev/null 2>&1
if [[ "$(cat "$CHECK_FILE")" == 'docs: update the readme.' ]]; then
  echo "✓ --check leaves the file untouched"
  PASS=$((PASS + 1))
else
  echo "✗ --check leaves the file untouched"
  FAIL=$((FAIL + 1))
fi

# --- normalizing is idempotent ----------------------------------------------
IDEM="$TMPDIR_TEST/idem"
printf '%s' "$TRAILER_MSG" > "$IDEM"
"$NORMALIZE" "$IDEM" >/dev/null 2>&1
FIRST="$(cat "$IDEM")"
"$NORMALIZE" "$IDEM" >/dev/null 2>&1
if [[ "$(cat "$IDEM")" == "$FIRST" ]]; then
  echo "✓ normalizing is idempotent"
  PASS=$((PASS + 1))
else
  echo "✗ normalizing is idempotent"
  FAIL=$((FAIL + 1))
fi

echo ""
if (( FAIL > 0 )); then
  echo "❌ $FAIL failed, $PASS passed"
  exit 1
fi
echo "✅ all $PASS tests passed"
