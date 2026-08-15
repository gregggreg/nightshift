#!/usr/bin/env sh
# Tests for scripts/normalize-commit-msg.sh and scripts/validate-commit-msg.sh.
# Run: make test-commit-msg   (or: sh scripts/tests/commit-msg.test.sh)
set -eu

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SCRIPTS=$(CDPATH='' cd -- "$TEST_DIR/.." && pwd)
NORMALIZE="$SCRIPTS/normalize-commit-msg.sh"
VALIDATE="$SCRIPTS/validate-commit-msg.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/commit-msg-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

msg_file() {
	f="$WORK/msg"
	# %b so tests can express trailing whitespace with an explicit \n
	printf '%b' "$1" >"$f"
	printf '%s' "$f"
}

# normalizes <name> <input> <expected output>
normalizes() {
	name=$1
	f=$(msg_file "$2")
	if ! "$NORMALIZE" "$f" >"$WORK/out" 2>&1; then
		FAIL=$((FAIL + 1))
		echo "✗ $name — normalizer exited non-zero"
		sed 's/^/    /' "$WORK/out"
		return 0
	fi
	got=$(cat "$f")
	want=$(printf '%b' "$3")
	if [ "$got" = "$want" ]; then
		PASS=$((PASS + 1))
		echo "✓ $name"
	else
		FAIL=$((FAIL + 1))
		echo "✗ $name"
		echo "    want: $(printf '%s' "$want" | sed -n '1,20p' | sed 's/^/      /' | tr '\n' '@')"
		echo "    got:  $(printf '%s' "$got" | sed -n '1,20p' | sed 's/^/      /' | tr '\n' '@')"
	fi
}

# accepts <name> <message>
accepts() {
	f=$(msg_file "$2")
	if "$VALIDATE" "$f" >"$WORK/out" 2>&1; then
		PASS=$((PASS + 1))
		echo "✓ $1"
	else
		FAIL=$((FAIL + 1))
		echo "✗ $1 — expected accept, got reject"
		sed 's/^/    /' "$WORK/out"
	fi
}

# rejects <name> <message> <expected substring in the error>
rejects() {
	f=$(msg_file "$2")
	if "$VALIDATE" "$f" >"$WORK/out" 2>&1; then
		FAIL=$((FAIL + 1))
		echo "✗ $1 — expected reject, got accept"
		return 0
	fi
	if grep -qF "$3" "$WORK/out"; then
		PASS=$((PASS + 1))
		echo "✓ $1"
	else
		FAIL=$((FAIL + 1))
		echo "✗ $1 — rejected, but the message did not mention '$3'"
		sed 's/^/    /' "$WORK/out"
	fi
}

# hook_accepts <name> <message> — full hook path: normalize then validate.
hook_accepts() {
	f=$(msg_file "$2")
	if "$NORMALIZE" "$f" >"$WORK/out" 2>&1 && "$VALIDATE" "$f" >>"$WORK/out" 2>&1; then
		PASS=$((PASS + 1))
		echo "✓ $1"
	else
		FAIL=$((FAIL + 1))
		echo "✗ $1 — hook rejected a message it should have normalized"
		sed 's/^/    /' "$WORK/out"
	fi
}

echo "commit message normalizer"

normalizes "conforming message is untouched" \
	'feat(runner): add a retry budget
' \
	'feat(runner): add a retry budget
'

normalizes "trailing period is stripped" \
	'fix: guard against a nil provider.
' \
	'fix: guard against a nil provider
'

normalizes "capitalized verb is lowercased" \
	'fix: Guard against a nil provider
' \
	'fix: guard against a nil provider
'

normalizes "capitalized type is lowercased" \
	'Fix: guard against a nil provider
' \
	'fix: guard against a nil provider
'

normalizes "missing space after colon is inserted" \
	'fix:guard against a nil provider
' \
	'fix: guard against a nil provider
'

normalizes "scope and breaking marker survive normalization" \
	'Feat(config)!: Drop the legacy schema.
' \
	'feat(config)!: drop the legacy schema
'

normalizes "proper noun after the type is left alone" \
	'docs: Nightshift now documents its hooks
' \
	'docs: Nightshift now documents its hooks
'

normalizes "trailing whitespace is stripped" \
	'chore: tidy the makefile   \n' \
	'chore: tidy the makefile\n'

normalizes "blank line is inserted before the body" \
	'fix: guard against a nil provider
the provider map was read before it was populated.
' \
	'fix: guard against a nil provider

the provider map was read before it was populated.
'

normalizes "extra blank lines before the body collapse to one" \
	'fix: guard against a nil provider



the provider map was read before it was populated.
' \
	'fix: guard against a nil provider

the provider map was read before it was populated.
'

normalizes "body, interior blank lines and trailers are preserved verbatim" \
	'fix: Guard against a nil provider.

The provider map was read before it was populated.

Details:

  - one
  - two

Nightshift-Task: commit-normalize
Nightshift-Ref: https://github.com/marcus/nightshift
Co-Authored-By: Someone <someone@example.com>
' \
	'fix: guard against a nil provider

The provider map was read before it was populated.

Details:

  - one
  - two

Nightshift-Task: commit-normalize
Nightshift-Ref: https://github.com/marcus/nightshift
Co-Authored-By: Someone <someone@example.com>
'

normalizes "merge commits are left untouched" \
	'Merge pull request #46 from marcus/fix/navbar.
' \
	'Merge pull request #46 from marcus/fix/navbar.
'

normalizes "fixup commits are left untouched" \
	'fixup! feat: Add a retry budget.
' \
	'fixup! feat: Add a retry budget.
'

normalizes "git-generated reverts are left untouched" \
	'Revert "feat: add a retry budget."
' \
	'Revert "feat: add a retry budget."
'

normalizes "unparseable subjects are left alone apart from safe fixes" \
	'Update makefile, selector
' \
	'Update makefile, selector
'

normalizes "git comments are preserved" \
	'fix: Guard against a nil provider.

# Please enter the commit message for your changes.
# On branch main
' \
	'fix: guard against a nil provider

# Please enter the commit message for your changes.
# On branch main
'

echo ""
echo "commit message validator"

accepts "conforming subject" 'feat(runner): add a retry budget
'
accepts "breaking change marker" 'feat(config)!: drop the legacy schema
'
accepts "subject with body and trailers" 'fix: guard against a nil provider

The provider map was read before it was populated.

Nightshift-Task: commit-normalize
'
accepts "72-character subject is at the limit" 'feat: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
'
accepts "merge commit is exempt" 'Merge pull request #46 from marcus/fix/navbar
'
accepts "fixup commit is exempt" 'fixup! feat: add a retry budget
'
accepts "squash commit is exempt" 'squash! feat: add a retry budget
'
accepts "git-generated revert is exempt" 'Revert "feat: add a retry budget"
'
accepts "revert type is allowed" 'revert: feat: add a retry budget
'

rejects "missing type" 'Update makefile, selector
' "no type prefix"

rejects "unknown type" 'chores: tidy the makefile
' "unknown type 'chores'"

rejects "uppercase type survives as malformed" 'Fix: guard against a nil provider
' "malformed type prefix"

rejects "empty description" 'fix:
' "empty description"

rejects "description is only whitespace" 'fix:   
' "empty description"

accepts "squash-merge PR suffix does not count toward the limit" 'feat: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa (#123)
'

rejects "73-character subject" 'feat: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
' "limit is 72"

rejects "trailing period" 'fix: guard against a nil provider.
' "ends with a period"

rejects "missing space after the colon" 'fix:guard against a nil provider
' "missing space after the colon"

rejects "body not separated by a blank line" 'fix: guard against a nil provider
the provider map was read before it was populated.
' "no blank line"

rejects "empty message" '' "the message is empty"

rejects "comments only" '# On branch main
' "the message is empty"

echo ""
echo "hook (normalize, then validate)"

hook_accepts "a fixable message passes the hook" 'Fix: Guard against a nil provider.
the provider map was read before it was populated.
'
hook_accepts "an already conforming message passes the hook" 'feat(runner): add a retry budget
'

echo ""
if [ "$FAIL" -gt 0 ]; then
	echo "❌ $FAIL failed, $PASS passed"
	exit 1
fi
echo "✅ all $PASS checks passed"
