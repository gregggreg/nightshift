#!/usr/bin/env bash
#
# Validate a commit message against docs/commit-conventions.md.
#
# usage: validate-commit-msg.sh <commit-message-file>
#        validate-commit-msg.sh --subject "feat(run): add pause command"
#
# Exits 0 when the message conforms (or is a git-generated message that must
# never be blocked), 1 with one diagnostic line per violated rule otherwise.
set -euo pipefail

# shellcheck source=scripts/commit-msg-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/commit-msg-lib.sh"

SUBJECT_ONLY=0
INPUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --subject) SUBJECT_ONLY=1; shift; INPUT="${1-}"; shift || true ;;
    -h|--help) echo "usage: $0 <commit-message-file> | --subject <text>"; exit 0 ;;
    -*) echo "validate-commit-msg: unknown option: $1" >&2; exit 2 ;;
    *)
      if [ -n "$INPUT" ]; then
        echo "validate-commit-msg: unexpected argument: $1" >&2
        exit 2
      fi
      INPUT=$1; shift ;;
  esac
done

lines=()
if [ "$SUBJECT_ONLY" -eq 1 ]; then
  [ -n "$INPUT" ] || { echo "validate-commit-msg: --subject requires text" >&2; exit 2; }
  lines=("$INPUT")
else
  if [ -z "$INPUT" ]; then
    echo "usage: $0 <commit-message-file> | --subject <text>" >&2
    exit 2
  fi
  if [ ! -r "$INPUT" ]; then
    echo "validate-commit-msg: not a readable file: $INPUT" >&2
    exit 2
  fi
  commit_msg_read_lines "$INPUT"
  lines=(${COMMIT_MSG_LINES[@]+"${COMMIT_MSG_LINES[@]}"})
fi

# Everything from git's scissors marker on is stripped by git (raw diff under
# `git commit -v`), so it is not part of the message being validated.
commit_msg_find_cut ${lines[@]+"${lines[@]}"}
cut=$COMMIT_MSG_CUT

# Drop git comment lines; they are stripped before the message is stored.
content=()
for (( i = 0; i < cut; i++ )); do
  line="${lines[$i]}"
  commit_msg_is_comment "$line" && continue
  content+=("$line")
done

first_line="$(commit_msg_first_content_line ${content[@]+"${content[@]}"})"
if commit_msg_is_generated "$first_line"; then
  exit 0
fi

errors=()
add_error() { errors+=("$1"); }

subject_index=-1
for i in "${!content[@]}"; do
  if [ -n "${content[$i]//[[:space:]]/}" ]; then
    subject_index=$i
    break
  fi
done

if [ "$subject_index" -lt 0 ]; then
  echo "commit message is empty" >&2
  exit 1
fi

subject="${content[$subject_index]}"

if [ "$subject" != "$(commit_msg_collapse_spaces "$subject")" ]; then
  add_error "subject has leading, trailing, or repeated whitespace"
fi

collapsed="$(commit_msg_collapse_spaces "$subject")"

if [ "${#collapsed}" -gt "$COMMIT_MSG_MAX_SUBJECT" ]; then
  add_error "subject is ${#collapsed} characters; the limit is $COMMIT_MSG_MAX_SUBJECT"
fi

if [[ $collapsed == *. && $collapsed != *.. ]]; then
  add_error "subject ends with a period"
fi

if commit_msg_split_subject "$collapsed"; then
  if [ "$CM_TYPE" != "${collapsed%%[(:!]*}" ]; then
    add_error "type must be lowercase: \"${collapsed%%[(:!]*}\" should be \"$CM_TYPE\""
  fi
  summary_first="${CM_SUMMARY%% *}"
  if [[ $summary_first =~ ^[A-Z][a-z]*[[:punct:]]?$ ]]; then
    add_error "summary should start lowercase and imperative: \"$CM_SUMMARY\""
  fi
else
  add_error "$CM_ERR"
fi

# Exactly one blank line must separate the subject from the body.
body_index=$(( subject_index + 1 ))
if [ "$body_index" -lt "${#content[@]}" ]; then
  has_body=0
  for (( i = body_index; i < ${#content[@]}; i++ )); do
    if [ -n "${content[$i]//[[:space:]]/}" ]; then has_body=1; break; fi
  done
  if [ "$has_body" -eq 1 ] && [ -n "${content[$body_index]//[[:space:]]/}" ]; then
    add_error "missing blank line between subject and body"
  fi
fi

if [ "${#errors[@]}" -eq 0 ]; then
  exit 0
fi

{
  echo "invalid commit message:"
  echo "  subject: $subject"
  for err in "${errors[@]}"; do
    echo "  - $err"
  done
  echo
  echo "expected: type(scope)!: summary   (see docs/commit-conventions.md)"
  echo "types:    $(commit_msg_types_csv)"
} >&2
exit 1
