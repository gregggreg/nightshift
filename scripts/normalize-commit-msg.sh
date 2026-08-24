#!/usr/bin/env bash
# normalize-commit-msg.sh — normalize/validate a commit message against the
# nightshift commit convention (see docs/commit-messages.md).
#
# Usage:
#   normalize-commit-msg.sh <file>            rewrite <file> in place
#   normalize-commit-msg.sh --check <file>    validate only, exit non-zero unless
#                                             <file> is already normalized
#
# Exit codes: 0 ok (or exempt), 1 message rejected, 2 usage error.
set -uo pipefail

ALLOWED_TYPES="build chore ci docs feat fix perf refactor revert style test"
MAX_SUBJECT=72
SCISSORS='# ------------------------ >8 ------------------------'

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

# --- read the message --------------------------------------------------------
# Only scaffolding that precedes the subject is dropped: leading blank lines and
# the leading comment block git may have prefilled. Comment lines *inside* the
# body are left alone — git runs its own cleanup after this hook returns, and
# that cleanup is flow-aware (it strips comments for editor-authored messages
# and deliberately keeps them for `git commit -m`). Stripping them here would
# delete body text that git would otherwise have kept.
#
# Everything from the scissors line onward is dropped: git only emits it under
# cleanup=scissors, where it discards that section itself.
CONTENT=""
STARTED=0
CRLF=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "${line%$'\r'}" == "$SCISSORS" ]] && break
  if (( ! STARTED )); then
    case "$line" in '#'*) continue ;; esac
    [[ -z "${line//[[:space:]]/}" ]] && continue
    STARTED=1
    [[ "$line" == *$'\r' ]] && CRLF=1
  fi
  CONTENT+="$line"$'\n'
done < "$FILE"

(( STARTED )) || fail "message is empty"

EOL=$'\n'
(( CRLF )) && EOL=$'\r\n'

SUBJECT="${CONTENT%%$'\n'*}"
REST="${CONTENT#*$'\n'}"

# Trim surrounding whitespace from the subject (this also drops a trailing CR).
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
# exactly one blank line separates it from the subject and that it ends in a
# single newline.
while [[ -n "$REST" ]]; do                     # drop blank lines after the subject
  first="${REST%%$'\n'*}"
  [[ -z "${first//[[:space:]]/}" ]] || break
  REST="${REST#*$'\n'}"
done
REST="${REST%$'\n'}"; REST="${REST%$'\r'}"     # drop the final line ending
while [[ "$REST" == *$'\n' ]]; do              # drop trailing blank lines
  last="${REST##*$'\n'}"
  [[ -z "${last//[[:space:]]/}" ]] || break
  REST="${REST%$'\n'*}"; REST="${REST%$'\r'}"
done
[[ -z "${REST//[[:space:]]/}" ]] && REST=""

if [[ -n "$REST" ]]; then
  NORMALIZED="${NEW_SUBJECT}${EOL}${EOL}${REST}${EOL}"
else
  NORMALIZED="${NEW_SUBJECT}${EOL}"
fi

if (( CHECK )); then
  # --check asserts the message is already normalized, not merely normalizable:
  # anything the in-place mode would rewrite is a violation to report.
  if [[ "$NORMALIZED" != "$CONTENT" ]]; then
    if [[ "$NEW_SUBJECT" != "$SUBJECT" ]]; then
      fail "subject should be '$NEW_SUBJECT', not '$SUBJECT'"
    fi
    fail "subject and body must be separated by exactly one blank line"
  fi
  exit 0
fi

printf '%s' "$NORMALIZED" > "$FILE"
exit 0
