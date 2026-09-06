#!/usr/bin/env bash
#
# Normalize a commit message file in place toward the Conventional Commits
# format documented in docs/commit-conventions.md.
#
# Normalization is deliberately conservative: it only rewrites things that are
# mechanically safe (whitespace, casing of a known type, a trailing period,
# subject/body separation). Semantic guesswork -- inserting a type that the
# author never wrote -- happens only behind --infer.
#
# usage: normalize-commit-msg.sh [--infer] <commit-message-file>
set -euo pipefail

INFER=0
FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --infer) INFER=1; shift ;;
    -h|--help)
      echo "usage: $0 [--infer] <commit-message-file>"
      exit 0
      ;;
    --) shift; FILE="${1:-}"; shift || true ;;
    -*)
      echo "normalize-commit-msg: unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [ -n "$FILE" ]; then
        echo "normalize-commit-msg: unexpected argument: $1" >&2
        exit 2
      fi
      FILE=$1
      shift
      ;;
  esac
done

if [ -z "$FILE" ]; then
  echo "usage: $0 [--infer] <commit-message-file>" >&2
  exit 2
fi

if [ ! -f "$FILE" ] || [ ! -r "$FILE" ] || [ ! -w "$FILE" ]; then
  echo "normalize-commit-msg: not a readable, writable file: $FILE" >&2
  exit 2
fi

# shellcheck source=scripts/commit-msg-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/commit-msg-lib.sh"

commit_msg_read_lines "$FILE"
ALL=(${COMMIT_MSG_LINES[@]+"${COMMIT_MSG_LINES[@]}"})

# Split off the scissors trailer. Under `git commit -v` everything from the
# scissors marker on is a raw, un-commented diff that git strips at commit
# time. It has to stay exactly where it is: hoisting comment lines above it
# would defeat git's stripping and commit the whole diff as the message body.
commit_msg_find_cut ${ALL[@]+"${ALL[@]}"}
CUT=$COMMIT_MSG_CUT

RAW=()
TAIL=()
for (( i = 0; i < ${#ALL[@]}; i++ )); do
  if [ "$i" -lt "$CUT" ]; then
    RAW+=("${ALL[$i]}")
  else
    TAIL+=("${ALL[$i]}")
  fi
done

# Git generates these subjects itself. Rewriting them breaks merges, reverts,
# autosquash and stash messages, so the file is left byte for byte intact.
first_line="$(commit_msg_first_content_line ${RAW[@]+"${RAW[@]}"})"
if commit_msg_is_generated "$first_line"; then
  exit 0
fi

content=()
comments=()
for line in ${RAW[@]+"${RAW[@]}"}; do
  if commit_msg_is_comment "$line"; then
    comments+=("$line")
  else
    content+=("${line%"${line##*[![:space:]]}"}")   # drop trailing whitespace
  fi
done

# Trim leading and trailing blank lines from the content block.
start=0
end=$(( ${#content[@]} - 1 ))
while [ "$start" -le "$end" ] && [ -z "${content[$start]}" ]; do start=$(( start + 1 )); done
while [ "$end" -ge "$start" ] && [ -z "${content[$end]}" ]; do end=$(( end - 1 )); done

if [ "$start" -gt "$end" ]; then
  exit 0   # nothing but blanks and comments; let git reject the empty message
fi

subject="${content[$start]}"
subject="$(commit_msg_collapse_spaces "$subject")"

if commit_msg_split_subject "$subject"; then
  subject="$(commit_msg_render_subject)"
else
  # Unrecognized shape: only mechanically safe cleanups, never a guessed type
  # unless the caller explicitly asked for one.
  subject="$(commit_msg_strip_trailing_period "$subject")"
  if [ "$INFER" -eq 1 ]; then
    subject="chore: $(commit_msg_normalize_summary "$subject")"
  fi
fi

# Rebuild: subject, blank line, body with runs of blank lines collapsed to one.
out=("$subject")
body=()
prev_blank=1
for (( i = start + 1; i <= end; i++ )); do
  line="${content[$i]}"
  if [ -z "$line" ]; then
    if [ "$prev_blank" -eq 0 ]; then
      body+=("")
    fi
    prev_blank=1
  else
    body+=("$line")
    prev_blank=0
  fi
done

# Drop a leading blank produced by trimming, then re-add exactly one separator.
if [ "${#body[@]}" -gt 0 ] && [ -z "${body[0]}" ]; then
  body=("${body[@]:1}")
fi
if [ "${#body[@]}" -gt 0 ]; then
  out+=("")
  out+=("${body[@]}")
fi

if [ "${#comments[@]}" -gt 0 ]; then
  out+=("${comments[@]}")
fi

# The scissors trailer is re-emitted verbatim, still last and still intact.
if [ "${#TAIL[@]}" -gt 0 ]; then
  out+=("${TAIL[@]}")
fi

printf '%s\n' "${out[@]}" > "$FILE"
