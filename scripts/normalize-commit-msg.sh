#!/usr/bin/env bash
# normalize-commit-msg.sh — normalize/validate a commit message against the
# nightshift commit convention (see docs/commit-messages.md).
#
# Usage:
#   normalize-commit-msg.sh <file>            rewrite <file> in place
#   normalize-commit-msg.sh --check <file>    validate only, exit non-zero on failure
#
# Exit codes: 0 ok (or exempt), 1 message cannot be normalized, 2 usage error.
set -uo pipefail

ALLOWED_TYPES="build chore ci docs feat fix perf refactor revert style test"
MAX_SUBJECT=72

usage() {
  echo "usage: $(basename "$0") [--check] <commit-msg-file>" >&2
  exit 2
}

CHECK=0
FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *) [[ -n "$FILE" ]] && usage; FILE="$1"; shift ;;
  esac
done
[[ -n "$FILE" ]] || usage
[[ -f "$FILE" ]] || { echo "no such file: $FILE" >&2; exit 2; }

fail() {
  echo "✗ commit message rejected: $1" >&2
  echo "" >&2
  echo "  Expected: <type>(<scope>)!: <subject>" >&2
  echo "  Types:    ${ALLOWED_TYPES// /, }" >&2
  echo "  See docs/commit-messages.md" >&2
  exit 1
}

# --- read the raw message, dropping scissors/comment scaffolding -------------
RAW=""
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    '# ------------------------ >8 ------------------------') break ;;
    '#'*) continue ;;
  esac
  RAW+="$line"$'\n'
done < "$FILE"

# Strip leading blank lines.
BODY_ALL="${RAW#"${RAW%%[![:space:]]*}"}"
if [[ -z "$BODY_ALL" ]]; then
  fail "message is empty"
fi

SUBJECT="${BODY_ALL%%$'\n'*}"
if [[ "$BODY_ALL" == *$'\n'* ]]; then
  REST="${BODY_ALL#*$'\n'}"
else
  REST=""
fi

# Trim surrounding whitespace from the subject.
SUBJECT="${SUBJECT#"${SUBJECT%%[![:space:]]*}"}"
SUBJECT="${SUBJECT%"${SUBJECT##*[![:space:]]}"}"

# --- exemptions: never rewrite these ----------------------------------------
case "$SUBJECT" in
  Merge\ *|Revert\ *|revert!*|fixup!\ *|squash!\ *|amend!\ *)
    exit 0 ;;
esac

# --- normalize the subject ---------------------------------------------------

HEADER_RE='^([A-Za-z]+)(\(([^)]+)\))?(!)?:[[:space:]]*(.*)$'
if [[ ! "$SUBJECT" =~ $HEADER_RE ]]; then
  fail "subject '$SUBJECT' is not '<type>(<scope>)!: <subject>'"
fi

TYPE="${BASH_REMATCH[1]}"
SCOPE="${BASH_REMATCH[3]}"
BANG="${BASH_REMATCH[4]}"
DESC="${BASH_REMATCH[5]}"

# Lowercase the type; validate against the allowed set.
TYPE="$(printf '%s' "$TYPE" | tr '[:upper:]' '[:lower:]')"
case " $ALLOWED_TYPES " in
  *" $TYPE "*) ;;
  *) fail "unknown type '$TYPE'" ;;
esac

# Lowercase the scope (scopes are lowercase by convention).
[[ -n "$SCOPE" ]] && SCOPE="$(printf '%s' "$SCOPE" | tr '[:upper:]' '[:lower:]')"

# Trim the description and drop a single trailing period.
DESC="${DESC#"${DESC%%[![:space:]]*}"}"
DESC="${DESC%"${DESC##*[![:space:]]}"}"
[[ "$DESC" == *. && "$DESC" != *.. ]] && DESC="${DESC%.}"

if [[ -z "$DESC" ]]; then
  fail "subject has an empty description after '$TYPE:'"
fi

if [[ -n "$SCOPE" ]]; then
  NEW_SUBJECT="${TYPE}(${SCOPE})${BANG}: ${DESC}"
else
  NEW_SUBJECT="${TYPE}${BANG}: ${DESC}"
fi

# Warn (never fail) on an over-length subject. Measured in characters, not bytes.
SUBJECT_LEN=$(printf '%s' "$NEW_SUBJECT" | wc -m | tr -d ' ')
if (( SUBJECT_LEN > MAX_SUBJECT )); then
  echo "⚠ subject is ${SUBJECT_LEN} chars (soft limit ${MAX_SUBJECT}); consider shortening" >&2
fi

# --- rebuild: subject, blank line, body/trailers byte-for-byte ---------------
# REST keeps the body and every trailer untouched; we only guarantee that
# exactly one blank line separates it from the subject.
REST="${REST#"${REST%%[!$'\n']*}"}"           # drop any blank lines after the subject
REST="${REST%"${REST##*[!$'\n']}"}"        # drop trailing newlines; re-added below

if [[ -n "$REST" ]]; then
  NORMALIZED="${NEW_SUBJECT}"$'\n\n'"${REST}"$'\n'
else
  NORMALIZED="${NEW_SUBJECT}"$'\n'
fi

if (( CHECK )); then
  exit 0
fi

printf '%s' "$NORMALIZED" > "$FILE"
exit 0
