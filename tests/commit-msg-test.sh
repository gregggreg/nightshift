#!/usr/bin/env bash
#
# Table-driven regression tests for the commit-message normalizer and
# validator. No external test framework required.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NORMALIZE="$ROOT/scripts/normalize-commit-msg.sh"
VALIDATE="$ROOT/scripts/validate-commit-msg.sh"

PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  FAIL=$((FAIL + 1))
  echo "✗ $1"
  shift
  printf '    %s\n' "$@"
}

pass() {
  PASS=$((PASS + 1))
  echo "✓ $1"
}

# normalize <name> <input> <expected-output> [--infer]
normalize_case() {
  local name=$1 input=$2 expected=$3 infer=${4-}
  local file="$WORK/msg"
  printf '%s' "$input" > "$file"
  if [ -n "$infer" ]; then
    "$NORMALIZE" --infer "$file" >/dev/null 2>&1
  else
    "$NORMALIZE" "$file" >/dev/null 2>&1
  fi
  local actual
  actual="$(cat "$file")"
  if [ "$actual" = "$expected" ]; then
    pass "normalize: $name"
  else
    fail "normalize: $name" "expected: $(printf '%q' "$expected")" "actual:   $(printf '%q' "$actual")"
  fi
}

# normalize_with_comment_prefix <name> <config-key> <prefix> <input> <expected>
normalize_with_comment_prefix() {
  local name=$1 key=$2 prefix=$3 input=$4 expected=$5
  local file="$WORK/msg"
  printf '%s' "$input" > "$file"
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="core.$key" GIT_CONFIG_VALUE_0="$prefix" \
    "$NORMALIZE" "$file" >/dev/null 2>&1
  local actual
  actual="$(cat "$file")"
  if [ "$actual" = "$expected" ]; then
    pass "normalize ($key=$prefix): $name"
  else
    fail "normalize ($key=$prefix): $name" "expected: $(printf '%q' "$expected")" "actual:   $(printf '%q' "$actual")"
  fi
}

# valid <name> <message>
valid_case() {
  local name=$1 msg=$2
  local file="$WORK/msg"
  printf '%s\n' "$msg" > "$file"
  local out
  if out="$("$VALIDATE" "$file" 2>&1)"; then
    pass "validate accepts: $name"
  else
    fail "validate accepts: $name" "$out"
  fi
}

# invalid <name> <message> <expected-substring>
invalid_case() {
  local name=$1 msg=$2 needle=$3
  local file="$WORK/msg"
  printf '%s\n' "$msg" > "$file"
  local out status
  out="$("$VALIDATE" "$file" 2>&1)"; status=$?
  if [ "$status" -eq 0 ]; then
    fail "validate rejects: $name" "expected rejection, got exit 0"
  elif [[ $out != *"$needle"* ]]; then
    fail "validate rejects: $name" "expected diagnostic containing: $needle" "actual: $out"
  else
    pass "validate rejects: $name"
  fi
}

echo "commit-msg normalization"
normalize_case "trailing whitespace" \
  'feat(run): add pause command   ' \
  'feat(run): add pause command'

normalize_case "trailing period on subject" \
  'fix: stop double-counting budget.' \
  'fix: stop double-counting budget'

normalize_case "ellipsis is preserved" \
  'chore: work in progress...' \
  'chore: work in progress...'

normalize_case "uppercase type is lowercased" \
  'Fix(config): reject unknown keys' \
  'fix(config): reject unknown keys'

normalize_case "capitalized summary is lowercased" \
  'feat: Add pause command' \
  'feat: add pause command'

normalize_case "acronym summary is preserved" \
  'feat: API key rotation' \
  'feat: API key rotation'

normalize_case "spacing around scope and bang" \
  'feat ( run ) ! :   add   pause   command' \
  'feat(run)!: add pause command'

normalize_case "blank line inserted between subject and body" \
  'fix: guard nil provider
the provider can be nil after a failed load.' \
  'fix: guard nil provider

the provider can be nil after a failed load.'

normalize_case "repeated blank lines collapse" \
  'fix: guard nil provider


body line one


body line two' \
  'fix: guard nil provider

body line one

body line two'

normalize_case "leading blank lines trimmed" \
  '

docs: explain hooks' \
  'docs: explain hooks'

normalize_case "trailers are preserved verbatim" \
  'chore: bump version

Nightshift-Task: commit-normalize
Nightshift-Ref: https://github.com/marcus/nightshift' \
  'chore: bump version

Nightshift-Task: commit-normalize
Nightshift-Ref: https://github.com/marcus/nightshift'

normalize_case "merge commits are untouched" \
  'Merge pull request #17 from cedricfarinazzo/nightshift-lint-fixes   ' \
  'Merge pull request #17 from cedricfarinazzo/nightshift-lint-fixes   '

normalize_case "revert commits are untouched" \
  'Revert "feat: add pause command."' \
  'Revert "feat: add pause command."'

normalize_case "fixup commits are untouched" \
  'fixup! feat: add pause command.' \
  'fixup! feat: add pause command.'

normalize_case "squash commits are untouched" \
  'squash! feat: add pause command.' \
  'squash! feat: add pause command.'

normalize_case "comment-only template is untouched" \
  '# Please enter the commit message for your changes.' \
  '# Please enter the commit message for your changes.'

normalize_case "git comments survive normalization" \
  'feat: add pause command.
# Please enter the commit message for your changes.' \
  'feat: add pause command
# Please enter the commit message for your changes.'

normalize_case "no type is left alone without --infer" \
  'add pause command' \
  'add pause command'

normalize_case "no type gains chore with --infer" \
  'Add pause command.' \
  'chore: add pause command' \
  --infer

normalize_with_comment_prefix "comment-only template is untouched" \
  commentChar ';' \
  '; Please enter the commit message for your changes.' \
  '; Please enter the commit message for your changes.'

normalize_with_comment_prefix "multi-character comment string is honored" \
  commentString '//' \
  'feat: add pause command.
// Lines starting with // will be ignored.' \
  'feat: add pause command
// Lines starting with // will be ignored.'

normalize_with_comment_prefix "# is body text when another prefix is configured" \
  commentChar ';' \
  'feat: add pause command.

# not a comment here' \
  'feat: add pause command

# not a comment here'

echo
echo "commit-msg validation"
valid_case "plain type" 'docs: explain hook installation'
valid_case "scoped type" 'feat(run): add pause command'
valid_case "breaking change" 'fix(config)!: reject unknown provider keys'
valid_case "subject and body" 'fix: guard nil provider

The provider can be nil after a failed load.'
valid_case "merge commit" 'Merge pull request #17 from example/branch'
valid_case "revert commit" 'Revert "feat: add pause command."'
valid_case "fixup commit" 'fixup! feat: add pause command'
valid_case "path-like scope" 'ci(.github/workflows): pin action versions'

invalid_case "unknown type" 'wip: half a feature' 'unknown type'
invalid_case "missing colon" 'add pause command' 'missing "type: " prefix'
invalid_case "empty summary" 'feat:' 'empty summary after "feat:"'
invalid_case "empty scoped summary" 'feat(run):   ' 'empty summary'
invalid_case "trailing period" 'feat: add pause command.' 'ends with a period'
invalid_case "uppercase type" 'Feat: add pause command' 'must be lowercase'
invalid_case "capitalized summary" 'feat: Add pause command' 'start lowercase'
invalid_case "malformed scope" 'feat(run: add pause command' 'malformed scope'
invalid_case "over-length subject" \
  "feat(run): $(printf 'x%.0s' {1..70})" \
  'the limit is 72'
invalid_case "missing blank line before body" 'fix: guard nil provider
the provider can be nil.' 'missing blank line between subject and body'

echo
echo "scissors (git commit -v)"

SCISSORS='# ------------------------ >8 ------------------------'

# The diff below the scissors line must stay below it. Hoisting comment lines
# above the marker would defeat git's scissors stripping and commit the diff.
normalize_case "diff below scissors is left in place" \
  "feat: add pause command.

# Please enter the commit message for your changes.
$SCISSORS
# Do not modify or remove the line above.
diff --git a/a.txt b/a.txt
index e69de29..7898192 100644
--- a/a.txt
+++ b/a.txt
@@ -0,0 +1 @@
+a
" \
  "feat: add pause command
# Please enter the commit message for your changes.
$SCISSORS
# Do not modify or remove the line above.
diff --git a/a.txt b/a.txt
index e69de29..7898192 100644
--- a/a.txt
+++ b/a.txt
@@ -0,0 +1 @@
+a"

normalize_case "body above scissors is still normalized" \
  "Feat(run):   Add pause command.
Explains why.

$SCISSORS
diff --git a/a.txt b/a.txt
" \
  "feat(run): add pause command

Explains why.
$SCISSORS
diff --git a/a.txt b/a.txt"

normalize_case "template with only a scissors block is untouched" \
  "
# Please enter the commit message for your changes.
$SCISSORS
diff --git a/a.txt b/a.txt
" \
  "
# Please enter the commit message for your changes.
$SCISSORS
diff --git a/a.txt b/a.txt"

normalize_with_comment_prefix "scissors honors a configured comment prefix" \
  commentChar ';' \
  "feat: add pause command.

; ------------------------ >8 ------------------------
diff --git a/a.txt b/a.txt
" \
  "feat: add pause command
; ------------------------ >8 ------------------------
diff --git a/a.txt b/a.txt"

# A body line that merely mentions ">8" is not a scissors marker.
normalize_case "lookalike body line is not treated as scissors" \
  "feat: add pause command.

see >8 for details
" \
  "feat: add pause command

see >8 for details"

valid_case "message with a scissors diff below it" "feat: add pause command

$SCISSORS
diff --git a/a.txt b/a.txt
+not a commit message body"

echo
echo "end-to-end: git commit -v with the hook installed"

# The regression this guards: `git commit -v` appends a scissors marker plus a
# raw diff to the message file. If the hook reorders anything across that
# marker, git stops stripping the diff and it lands in the commit body.
E2E="$WORK/e2e"
rm -rf "$E2E"
mkdir -p "$E2E/hooks" "$E2E/repo/scripts"
cp "$ROOT/.githooks/commit-msg" "$E2E/hooks/commit-msg"
cp "$ROOT/scripts/commit-msg-lib.sh" "$ROOT/scripts/normalize-commit-msg.sh" \
   "$ROOT/scripts/validate-commit-msg.sh" "$E2E/repo/scripts/"
chmod +x "$E2E/hooks/commit-msg" "$E2E/repo/scripts/"*.sh

cat > "$E2E/editor.sh" <<'EDITOR'
#!/usr/bin/env bash
# Stand-in for the user's editor: type a subject above git's template.
set -eu
tmp="$1.typed"
printf 'Feat(run):   Add pause command.\n' > "$tmp"
cat "$1" >> "$tmp"
mv "$tmp" "$1"
EDITOR
chmod +x "$E2E/editor.sh"

e2e_log=""
if (
  cd "$E2E/repo" || exit 1
  git init -q . &&
  git config user.email test@example.com &&
  git config user.name "Test User" &&
  git config commit.gpgsign false &&
  git config core.hooksPath "$E2E/hooks" &&
  printf 'a\n' > a.txt &&
  git add a.txt scripts &&
  GIT_EDITOR="$E2E/editor.sh" git commit -v -q
) >"$WORK/e2e.log" 2>&1; then
  e2e_log="$(git -C "$E2E/repo" log -1 --pretty=%B | sed -e '/^$/{$d;}')"
  if [ "$e2e_log" = "feat(run): add pause command" ]; then
    pass "git commit -v commits a clean subject and no diff"
  else
    fail "git commit -v commits a clean subject and no diff" \
      "expected: $(printf '%q' 'feat(run): add pause command')" \
      "actual:   $(printf '%q' "$e2e_log")"
  fi
else
  fail "git commit -v commits a clean subject and no diff" \
    "scratch commit failed:" "$(cat "$WORK/e2e.log")"
fi

echo
echo "--subject mode"
if "$VALIDATE" --subject 'feat(run): add pause command' >/dev/null 2>&1; then
  pass "--subject accepts a valid subject"
else
  fail "--subject accepts a valid subject" "unexpected rejection"
fi
if "$VALIDATE" --subject 'wip: nope' >/dev/null 2>&1; then
  fail "--subject rejects an invalid subject" "expected rejection, got exit 0"
else
  pass "--subject rejects an invalid subject"
fi

echo
if [ "$FAIL" -gt 0 ]; then
  echo "❌ $FAIL failed, $PASS passed"
  exit 1
fi
echo "✅ all $PASS checks passed"
