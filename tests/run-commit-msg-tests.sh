#!/usr/bin/env bash
# Tests for scripts/normalize-commit-msg.sh and scripts/validate-commit-msg.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NORMALIZE="$ROOT/scripts/normalize-commit-msg.sh"
VALIDATE="$ROOT/scripts/validate-commit-msg.sh"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

fail() {
  FAIL=$((FAIL + 1))
  echo "  ✗ $1"
  shift
  for line in "$@"; do echo "      $line"; done
}

ok() {
  PASS=$((PASS + 1))
  echo "  ✓ $1"
}

# Overrides core.commentChar for a single script run without touching any real
# git config, so the "honours core.commentChar" cases stay hermetic.
with_comment_char() {
  local char="$1"
  shift
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.commentChar GIT_CONFIG_VALUE_0="$char" "$@"
}

# normalize_of <message> [commentchar] -> prints normalized message
normalize_of() {
  local f="$TMPDIR_TEST/msg.$$"
  printf '%s' "$1" > "$f"
  if [[ "${2:-}" == "commentchar" ]]; then
    with_comment_char ';' "$NORMALIZE" "$f" >/dev/null 2>&1
  else
    "$NORMALIZE" "$f" >/dev/null 2>&1
  fi
  cat "$f"
  rm -f "$f"
}

# assert_normalizes <name> <input> <expected> [commentchar]
assert_normalizes() {
  local name="$1" input="$2" expected="$3" mode="${4:-}" actual
  actual="$(normalize_of "$input" "$mode")"
  if [[ "$actual" == "$expected" ]]; then
    ok "$name"
  else
    fail "$name" "expected: $(printf '%q' "$expected")" "actual:   $(printf '%q' "$actual")"
  fi
}

# assert_idempotent <name> <input> [commentchar]
assert_idempotent() {
  local name="$1" input="$2" mode="${3:-}" once twice
  once="$(normalize_of "$input" "$mode")"
  twice="$(normalize_of "$once" "$mode")"
  if [[ "$once" == "$twice" ]]; then
    ok "$name"
  else
    fail "$name" "once:  $(printf '%q' "$once")" "twice: $(printf '%q' "$twice")"
  fi
}

# assert_valid <name> <message>
assert_valid() {
  local name="$1" msg="$2" out
  out="$(printf '%s' "$msg" | "$VALIDATE" - 2>&1)"
  if [[ $? -eq 0 ]]; then ok "$name"; else fail "$name" "validator rejected it:" "$out"; fi
}

# assert_invalid <name> <message> [expected-substring]
assert_invalid() {
  local name="$1" msg="$2" needle="${3:-}" out rc
  out="$(printf '%s' "$msg" | "$VALIDATE" - 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then
    fail "$name" "validator accepted an invalid message"
  elif [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    fail "$name" "message did not mention '$needle':" "$out"
  else
    ok "$name"
  fi
}

echo "commit-msg normalizer tests"
echo ""
echo "normalization:"

assert_normalizes "already-valid message passes through" \
  'feat(api): add rate limiting' \
  'feat(api): add rate limiting'

assert_normalizes "Fix: Thing. -> fix: thing" \
  'Fix: Thing.' \
  'fix: thing'

assert_normalizes "breaking-change marker is preserved" \
  'Feat(api)!: Drop v1 endpoints.' \
  'feat(api)!: drop v1 endpoints'

assert_normalizes "dash separator becomes colon" \
  'feat(api) - add thing' \
  'feat(api): add thing'

assert_normalizes "bracket prefix becomes canonical" \
  '[feat] add thing' \
  'feat: add thing'

assert_normalizes "missing space after colon is fixed" \
  'fix:tighten timeout' \
  'fix: tighten timeout'

# A subject whose leading word happens to be a type but which is not
# conventional at all cannot be fixed unambiguously, so it is left exactly as
# written rather than half-rewritten on a commit that is rejected anyway.
assert_normalizes "unfixable subject is left untouched" \
  'Fix the bug' \
  'Fix the bug'

assert_normalizes "type word with no separator is left untouched" \
  'Feat something entirely different' \
  'Feat something entirely different'

assert_normalizes "acronyms in the description are preserved" \
  'feat: API key rotation' \
  'feat: API key rotation'

assert_normalizes "blank line is inserted between subject and body" \
  'fix: tighten timeout
the old value was too generous.' \
  'fix: tighten timeout

the old value was too generous.'

# Git does its own comment stripping *after* the commit-msg hook runs, and only
# when it would have: an editor-authored message loses its template, while
# `git commit -m` keeps a body line that happens to start with '#'. So the
# trailing template block is carved off and handed back untouched rather than
# deleted here, which would silently drop user-authored body text.
assert_normalizes "git template block is left intact for git to strip" \
  'Fix: Tighten timeout.
# Please enter the commit message for your changes.
# On branch main' \
  'fix: tighten timeout
# Please enter the commit message for your changes.
# On branch main'

assert_normalizes "a body line starting with # is not deleted" \
  'Fix: Thing.

#123 explains why. Do not lose me.' \
  'fix: thing

#123 explains why. Do not lose me.'

assert_normalizes "a # body line above a real template block survives" \
  'Fix: Thing.

#123 explains why.

# Please enter the commit message for your changes.' \
  'fix: thing

#123 explains why.

# Please enter the commit message for your changes.'

assert_normalizes "core.commentChar is honoured over a hardcoded #" \
  'Fix: Thing.

#123 explains why.
; On branch main' \
  'fix: thing

#123 explains why.
; On branch main' \
  commentchar

assert_normalizes "blank runs collapse and trailers survive" \
  'feat: add worker pool


Runs tasks concurrently.



Nightshift-Task: commit-normalize
Co-Authored-By: Someone <a@b.c>' \
  'feat: add worker pool

Runs tasks concurrently.

Nightshift-Task: commit-normalize
Co-Authored-By: Someone <a@b.c>'

assert_normalizes "blank line is inserted before the trailer block" \
  'feat: add worker pool
Runs tasks concurrently.
Nightshift-Task: commit-normalize
Co-Authored-By: Someone <a@b.c>' \
  'feat: add worker pool

Runs tasks concurrently.

Nightshift-Task: commit-normalize
Co-Authored-By: Someone <a@b.c>'

assert_normalizes "a single-word key at the end of the body is not a trailer" \
  'feat: add worker pool
Runs tasks concurrently.
Note: this is the last sentence.' \
  'feat: add worker pool

Runs tasks concurrently.
Note: this is the last sentence.'

assert_normalizes "merge commits are left untouched" \
  'Merge pull request #4 from marcus/feat/bus-factor-analyzer' \
  'Merge pull request #4 from marcus/feat/bus-factor-analyzer'

assert_normalizes "revert commits are left untouched" \
  'Revert "feat: Add Thing."' \
  'Revert "feat: Add Thing."'

assert_normalizes "fixup! commits are left untouched" \
  'fixup! feat: Add Thing.' \
  'fixup! feat: Add Thing.'

assert_normalizes "squash! commits are left untouched" \
  'squash! feat: Add Thing.' \
  'squash! feat: Add Thing.'

assert_normalizes "unrecognized subjects are not mangled" \
  'Update readme' \
  'Update readme'

echo ""
echo "idempotence:"
assert_idempotent "normalizing twice equals once (near-miss)" 'Fix: Thing.'
assert_idempotent "normalizing twice equals once (body + trailers)" \
  'Feat(api)!: Drop v1.
Body text here.
Nightshift-Task: commit-normalize
Co-Authored-By: Someone <a@b.c>'
assert_idempotent "normalizing twice equals once (merge)" \
  'Merge pull request #4 from marcus/x'

assert_idempotent "message with a git template block" 'Fix: Thing.

#123 explains why.

# Please enter the commit message for your changes.
# On branch main'

echo ""
echo "validation:"
assert_valid   "canonical message" 'feat(api): add rate limiting'
assert_valid   "breaking change"   'feat!: drop v1'
assert_valid   "merge commit"      'Merge pull request #4 from marcus/x'
assert_valid   "fixup commit"      'fixup! feat: add thing'
assert_valid   "body and trailers" 'fix: tighten timeout

Because it was too generous.

Nightshift-Task: commit-normalize'

assert_invalid "unknown type" 'update: readme' 'type'
assert_invalid "no type prefix" 'Update readme' 'type'
assert_invalid "empty subject" 'feat: ' 'subject'
assert_invalid "over-length subject" \
  "feat: $(printf 'x%.0s' {1..80})" '72'
# Subject length is a character count, not a byte count: an accented subject
# that is comfortably under the limit must not be rejected just because UTF-8
# spends two bytes on each accented letter.
assert_valid "multibyte subject under the limit is accepted" \
  "feat: $(printf 'é%.0s' {1..60})"
assert_invalid "multibyte subject over the limit is rejected" \
  "feat: $(printf 'é%.0s' {1..80})" '72'

assert_invalid "trailing period" 'feat: add thing.' 'period'
assert_invalid "capitalized subject" 'feat: Add thing' 'lowercase'
assert_invalid "missing blank line before body" 'feat: add thing
body starts immediately' 'blank line'

assert_valid "trailing git template block is ignored" 'fix: tighten timeout
# Please enter the commit message for your changes.
# On branch main'

# A '#' line with real content under it cannot be a git template, so it is
# body text and the missing blank line after the subject is still reported.
assert_invalid "a # body line is treated as body, not a comment" 'feat: add thing
#123 body starts immediately
and continues here' 'blank line'

# The unavoidable blind spot: a trailing '#' line is indistinguishable from a
# git template, so validation ignores it. Erring this way costs a missed
# warning; erring the other way would reject every editor-authored commit.
assert_valid "a trailing # line is assumed to be a template" 'feat: add thing
#123 could be either'

echo ""
echo "end-to-end (real git commit):"

# The regression this guards: the hook must not eat a body that git itself
# would have kept. With `git commit -m` git only strips whitespace, so a body
# line beginning with '#' has to survive all the way into the commit object.
e2e_repo="$TMPDIR_TEST/e2e"
mkdir -p "$e2e_repo"
(
  cd "$e2e_repo" || exit 1
  git init -q .
  git config user.email tests@example.com
  git config user.name tests
  # The hook resolves its scripts through the repo root, so give the scratch
  # repo a real copy of them and install the hook exactly as a developer would.
  mkdir -p scripts .git/hooks
  cp "$ROOT/scripts/normalize-commit-msg.sh" "$ROOT/scripts/validate-commit-msg.sh" \
    "$ROOT/scripts/commit-msg.sh" scripts/
  chmod +x scripts/*.sh
  ln -sf ../../scripts/commit-msg.sh .git/hooks/commit-msg
) >/dev/null 2>&1

e2e_commit() {
  (
    cd "$e2e_repo" || exit 1
    : > "file.$1"
    git add -A
    git commit -q "${@:2}" 2>&1
  )
}

e2e_message() { git -C "$e2e_repo" log -1 --pretty=%B; }

if e2e_commit body -m 'Fix: Thing.' -m '#123 explains why. Do not lose me.' >/dev/null 2>&1; then
  actual="$(e2e_message)"
  expected='fix: thing

#123 explains why. Do not lose me.'
  if [[ "$actual" == "$expected"* ]]; then
    ok "git commit -m keeps a # body line and still normalizes the subject"
  else
    fail "git commit -m keeps a # body line and still normalizes the subject" \
      "expected prefix: $(printf '%q' "$expected")" "actual:          $(printf '%q' "$actual")"
  fi
else
  fail "git commit -m keeps a # body line and still normalizes the subject" "the commit failed"
fi

e2e_editor_commit() {
  (
    cd "$e2e_repo" || exit 1
    : > "file.$1"
    git add -A
    printf '%s' "$2" > "$TMPDIR_TEST/editor-msg"
    GIT_EDITOR="cp $TMPDIR_TEST/editor-msg" git commit -q 2>&1
  )
}

if e2e_editor_commit editor 'Fix: Another thing.

# Please enter the commit message for your changes.
# On branch main' >/dev/null 2>&1; then
  actual="$(e2e_message)"
  if [[ "$actual" == 'fix: another thing'* && "$actual" != *'Please enter'* ]]; then
    ok "editor-authored template block is stripped by git, subject normalized"
  else
    fail "editor-authored template block is stripped by git, subject normalized" \
      "actual: $(printf '%q' "$actual")"
  fi
else
  fail "editor-authored template block is stripped by git, subject normalized" "the commit failed"
fi

echo ""
if [[ $FAIL -gt 0 ]]; then
  echo "❌ $FAIL failed, $PASS passed"
  exit 1
fi
echo "✅ all $PASS tests passed"
