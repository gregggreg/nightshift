#!/usr/bin/env bash
#
# Shared parsing helpers for the commit-message normalizer and validator.
# Sourced, never executed directly.

# Types allowed by docs/commit-conventions.md.
COMMIT_MSG_TYPES=(build chore ci docs feat fix perf refactor revert style test)

COMMIT_MSG_MAX_SUBJECT=72

# Parsed pieces of the most recent commit_msg_split_subject call.
CM_TYPE=""
CM_SCOPE=""
CM_BANG=""
CM_SUMMARY=""
CM_ERR=""

# Reads a file into the COMMIT_MSG_LINES array, stripping CR line endings.
# Written as a read loop rather than mapfile: macOS ships bash 3.2.
COMMIT_MSG_LINES=()
commit_msg_read_lines() {
  local line
  COMMIT_MSG_LINES=()
  while IFS= read -r line || [ -n "$line" ]; do
    COMMIT_MSG_LINES+=("${line%$'\r'}")
  done < "$1"
}

commit_msg_type_is_known() {
  local candidate=$1 known
  for known in "${COMMIT_MSG_TYPES[@]}"; do
    [ "$candidate" = "$known" ] && return 0
  done
  return 1
}

commit_msg_types_csv() {
  local out="" type
  for type in "${COMMIT_MSG_TYPES[@]}"; do
    out="${out:+$out, }$type"
  done
  printf '%s' "$out"
}

# Git's comment prefix, honoring core.commentChar / core.commentString.
# "auto" is reported as "#": git only picks another character when "#" would be
# ambiguous, and treating the message as uncommented is the safe fallback.
COMMIT_MSG_COMMENT_PREFIX=""
commit_msg_comment_prefix() {
  if [ -z "$COMMIT_MSG_COMMENT_PREFIX" ]; then
    local configured=""
    configured=$(git config --get core.commentString 2>/dev/null || true)
    if [ -z "$configured" ]; then
      configured=$(git config --get core.commentChar 2>/dev/null || true)
    fi
    case "$configured" in
      ""|auto) configured="#" ;;
    esac
    COMMIT_MSG_COMMENT_PREFIX=$configured
  fi
  printf '%s' "$COMMIT_MSG_COMMENT_PREFIX"
}

commit_msg_is_comment() {
  local prefix
  prefix="$(commit_msg_comment_prefix)"
  case "${1-}" in
    "$prefix"*) return 0 ;;
  esac
  return 1
}

# Git's scissors line, written by `git commit -v` / `commit.verbose` and by the
# "scissors" cleanup mode. Git truncates the message here, and everything below
# is a raw diff rather than comment-prefixed text. The normalizer must not move
# it or hoist anything above it, or the diff lands in the commit body.
commit_msg_is_scissors() {
  local prefix line=${1-}
  prefix="$(commit_msg_comment_prefix)"
  case "$line" in
    "$prefix"*) ;;
    *) return 1 ;;
  esac
  line="${line#"$prefix"}"
  [[ $line =~ ^[[:space:]-]*(\>8|8\<)[[:space:]-]*$ ]] || return 1
  return 0
}

# Index of the first scissors line in the given lines, or the line count when
# there is none. Callers treat everything from that index on as untouchable.
COMMIT_MSG_CUT=0
commit_msg_find_cut() {
  local line i=0
  COMMIT_MSG_CUT=$#
  for line in "$@"; do
    if commit_msg_is_scissors "$line"; then
      COMMIT_MSG_CUT=$i
      return 0
    fi
    i=$(( i + 1 ))
  done
  return 0
}

# Subjects that git writes on the author's behalf. Never rewritten, never
# rejected -- a hook that blocks `git merge` or `git rebase --autosquash` is
# worse than a slightly inconsistent history.
commit_msg_is_generated() {
  commit_msg_is_comment "${1-}" && return 0
  case "${1-}" in
    ""|"Merge "*|"Revert \""*|"fixup!"*|"squash!"*|"amend!"*|"WIP on "*|"index on "*)
      return 0 ;;
  esac
  return 1
}

# First line that is neither blank nor a git comment, with outer space trimmed.
commit_msg_first_content_line() {
  local line
  for line in "$@"; do
    line="${line#"${line%%[![:space:]]*}"}"
    [ -z "$line" ] && continue
    printf '%s' "$line"
    return 0
  done
  printf ''
}

commit_msg_collapse_spaces() {
  local value=$1
  value="${value//$'\t'/ }"
  while [[ $value == *"  "* ]]; do value="${value//  / }"; done
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# Strips exactly one sentence-ending period. "wip..." keeps its ellipsis.
commit_msg_strip_trailing_period() {
  local value=$1
  if [[ $value == *. && $value != *..  ]]; then
    value="${value%.}"
  fi
  printf '%s' "$value"
}

# Lowercases a leading capitalized word ("Add x" -> "add x") but leaves
# acronyms and mixed-case identifiers ("API", "gRPC", "macOS") alone.
commit_msg_normalize_summary() {
  local summary first rest
  summary="$(commit_msg_strip_trailing_period "$(commit_msg_collapse_spaces "$1")")"
  first="${summary%% *}"
  if [[ $first =~ ^[A-Z][a-z]*[[:punct:]]?$ ]]; then
    rest="${summary:1}"
    summary="$(tr '[:upper:]' '[:lower:]' <<<"${summary:0:1}")$rest"
  fi
  printf '%s' "$summary"
}

# Parses "type(scope)!: summary". Returns 0 and fills CM_* on success;
# returns 1 and sets CM_ERR to a human-readable reason otherwise.
commit_msg_split_subject() {
  local subject header
  subject="$(commit_msg_collapse_spaces "$1")"
  CM_TYPE=""; CM_SCOPE=""; CM_BANG=""; CM_SUMMARY=""; CM_ERR=""

  if [[ $subject != *:* ]]; then
    CM_ERR="missing \"type: \" prefix"
    return 1
  fi

  header="${subject%%:*}"
  CM_SUMMARY="$(commit_msg_collapse_spaces "${subject#*:}")"

  header="$(commit_msg_collapse_spaces "$header")"
  if [[ $header == *"!" ]]; then
    CM_BANG="!"
    header="$(commit_msg_collapse_spaces "${header%!}")"
  fi

  if [[ $header == *"("* || $header == *")"* ]]; then
    if [[ ! $header =~ ^([^()]+)\((.+)\)$ ]]; then
      CM_ERR="malformed scope; expected type(scope)"
      return 1
    fi
    header="$(commit_msg_collapse_spaces "${BASH_REMATCH[1]}")"
    CM_SCOPE="$(commit_msg_collapse_spaces "${BASH_REMATCH[2]}")"
    if [[ ! $CM_SCOPE =~ ^[A-Za-z0-9_./#-]+$ ]]; then
      CM_ERR="invalid scope \"$CM_SCOPE\""
      return 1
    fi
  fi

  CM_TYPE="$(tr '[:upper:]' '[:lower:]' <<<"$header")"
  if ! commit_msg_type_is_known "$CM_TYPE"; then
    CM_ERR="unknown type \"$header\" (allowed: $(commit_msg_types_csv))"
    return 1
  fi

  if [ -z "$CM_SUMMARY" ]; then
    CM_ERR="empty summary after \"$CM_TYPE:\""
    return 1
  fi

  return 0
}

# Canonical subject built from the last successful commit_msg_split_subject.
commit_msg_render_subject() {
  local scope=""
  [ -n "$CM_SCOPE" ] && scope="($CM_SCOPE)"
  printf '%s%s%s: %s' "$CM_TYPE" "$scope" "$CM_BANG" \
    "$(commit_msg_normalize_summary "$CM_SUMMARY")"
}
