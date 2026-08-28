#!/usr/bin/env bash
# commit-msg hook for nightshift — enforces Conventional Commits.
# Install: make install-hooks  (or: ln -sf ../../scripts/commit-msg.sh .git/hooks/commit-msg)
# Bypass:  git commit --no-verify
#
# Format: <type>[(<scope>)][!]: <description>
# See CONTRIBUTING.md for the full convention.
set -uo pipefail

TYPES="feat|fix|docs|chore|test|refactor|perf|build|ci|style|revert"
MAX_SUBJECT=72

MSG_FILE="${1:-}"
if [[ -z "$MSG_FILE" || ! -f "$MSG_FILE" ]]; then
  echo "commit-msg: no message file given" >&2
  exit 1
fi

# --- strip comments and the `commit -v` / scissors diff ---
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  # everything from the scissors marker onward is not part of the message
  if [[ "$line" == *"------------------------ >8 ------------------------"* ]]; then
    break
  fi
  [[ "$line" == "#"* ]] && continue
  LINES+=("$line")
done < "$MSG_FILE"

# --- locate the subject: first non-empty line ---
SUBJECT=""
SUBJECT_IDX=-1
for i in "${!LINES[@]}"; do
  if [[ -n "${LINES[$i]}" ]]; then
    SUBJECT="${LINES[$i]}"
    SUBJECT_IDX=$i
    break
  fi
done

# Empty message: git aborts the commit on its own.
[[ $SUBJECT_IDX -lt 0 ]] && exit 0

# --- commits git generates or rewrites later are exempt ---
case "$SUBJECT" in
  Merge\ *|Revert\ \"*|fixup!\ *|squash!\ *|amend!\ *) exit 0 ;;
esac

reject() {
  local rule="$1" fix="$2"
  echo "🪡 commit-msg check"
  printf "  %-20s %s\n" "subject" "✗ $rule"
  echo ""
  echo "    got:      $SUBJECT"
  echo "    expected: <type>[(<scope>)][!]: <description>"
  echo "    example:  $fix"
  echo ""
  echo "    types:    ${TYPES//|/, }"
  echo "    limits:   subject ≤ ${MAX_SUBJECT} chars, lowercase start, no trailing period"
  echo ""
  echo "❌ Commit message rejected. See CONTRIBUTING.md, or bypass with --no-verify."
  exit 1
}

# --- subject rules ---
if [[ "$SUBJECT" =~ ^[[:space:]] ]]; then
  reject "leading whitespace" "feat(budget): add daily calibration"
fi

if [[ ${#SUBJECT} -gt $MAX_SUBJECT ]]; then
  reject "too long (${#SUBJECT} chars, max ${MAX_SUBJECT})" "feat(budget): add daily calibration"
fi

if [[ ! "$SUBJECT" =~ ^($TYPES)(\([a-z0-9._/-]+\))?!?:\  ]]; then
  if [[ "$SUBJECT" != *:* ]]; then
    reject "missing '<type>: ' prefix" "feat(budget): add daily calibration"
  fi
  prefix="${SUBJECT%%:*}"
  reject "bad type or scope in '${prefix}:' (or missing space after the colon)" \
    "feat(budget): add daily calibration"
fi

DESC="${SUBJECT#*: }"

if [[ -z "$DESC" ]]; then
  reject "empty description" "feat(budget): add daily calibration"
fi

if [[ ! "$DESC" =~ ^[a-z] ]]; then
  reject "description must start with a lowercase letter" "feat: add daily calibration"
fi

if [[ "$DESC" == *. ]]; then
  reject "description must not end with a period" "feat: add daily calibration"
fi

# --- body rules: line 2 must be blank when a body follows ---
NEXT_IDX=$((SUBJECT_IDX + 1))
if [[ $NEXT_IDX -lt ${#LINES[@]} && -n "${LINES[$NEXT_IDX]}" ]]; then
  echo "🪡 commit-msg check"
  printf "  %-20s %s\n" "body" "✗ line 2 must be blank when a body follows the subject"
  echo ""
  echo "    got:      ${LINES[$NEXT_IDX]}"
  echo "    expected: an empty line between the subject and the body"
  echo ""
  echo "❌ Commit message rejected. See CONTRIBUTING.md, or bypass with --no-verify."
  exit 1
fi

exit 0
