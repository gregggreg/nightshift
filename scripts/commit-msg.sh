#!/bin/sh
# Validate a commit message against the nightshift commit convention.
#
# Usage: scripts/commit-msg.sh <commit-message-file>
#
# Installed as the `commit-msg` git hook by `make install-hooks`. The same
# validation is reused over a commit range by scripts/check-commit-range.sh.
#
# See docs/guides/commit-messages.md for the full convention.
set -eu

DOC_URL="docs/guides/commit-messages.md"
TYPES='feat|fix|docs|refactor|test|chore|build|ci|perf|style|revert'
MAX_SUBJECT=72
MAX_BODY=100

usage() {
	echo "usage: $0 <commit-message-file>" >&2
}

if [ "$#" -ne 1 ]; then
	usage
	exit 2
fi

message_file=$1
if [ ! -r "$message_file" ]; then
	echo "commit-msg: not a readable file: $message_file" >&2
	exit 2
fi

# Git may be configured to use a comment character other than '#'.
comment_char=$(git config --get core.commentChar 2>/dev/null || true)
case "$comment_char" in
"" | auto) comment_char='#' ;;
esac

# Strip comment lines and the scissors section git adds under --verbose.
stripped=$(
	awk -v c="$comment_char" '
		index($0, "------------------------ >8 ------------------------") { exit }
		substr($0, 1, length(c)) == c { next }
		{ sub(/\r$/, ""); print }
	' "$message_file"
)

# The subject is the first non-blank line.
subject=$(printf '%s\n' "$stripped" | awk 'NF { print; exit }')

if [ -z "$subject" ]; then
	echo "commit-msg: aborting due to empty commit message" >&2
	exit 1
fi

# Git authors these subjects itself. Rejecting them would break merges,
# reverts, and rebase autosquash, so let them through untouched.
case "$subject" in
"Merge "* | "Revert "* | "fixup!"* | "squash!"* | "amend!"* | "WIP on "* | "index on "*)
	exit 0
	;;
esac

errors=""
add_error() {
	errors="${errors}  - $1
"
}

# --- subject: structure -----------------------------------------------------
if ! printf '%s' "$subject" | grep -qE "^($TYPES)(\([a-z0-9._/#-]+\))?!?: .+"; then
	case "$subject" in
	*": "*)
		add_error "subject type is not one of: $(printf '%s' "$TYPES" | tr '|' ' ')"
		;;
	*)
		add_error "subject is missing the '<type>: ' prefix"
		;;
	esac
else
	description=${subject#*: }

	# --- subject: length ---
	length=$(printf '%s' "$subject" | wc -c | tr -d ' ')
	if [ "$length" -gt "$MAX_SUBJECT" ]; then
		add_error "subject is $length characters; keep it to $MAX_SUBJECT or fewer"
	fi

	# --- subject: no trailing period ---
	case "$description" in
	*.)
		add_error "subject must not end with a period"
		;;
	esac

	# --- subject: imperative, lowercase start ---
	# Reject "Add"/"Fix" style capitalization but allow acronyms (JSONL, PR, API).
	if printf '%s' "$description" | grep -qE '^[A-Z][a-z]'; then
		add_error "subject must start lowercase and be imperative (e.g. 'add', not 'Adds')"
	fi
fi

# --- body: blank line after subject ----------------------------------------
subject_line=$(printf '%s\n' "$stripped" | awk 'NF { print NR; exit }')
next_line=$(printf '%s\n' "$stripped" | awk -v s="$subject_line" 'NR == s + 1 { print }')
has_more=$(printf '%s\n' "$stripped" | awk -v s="$subject_line" 'NR > s + 1 && NF { print "yes"; exit }')

if [ -n "$next_line" ]; then
	add_error "separate the subject from the body with a blank line"
elif [ -n "$has_more" ]; then
	# --- body: line length ---
	long=$(
		printf '%s\n' "$stripped" | awk -v s="$subject_line" -v max="$MAX_BODY" '
			NR <= s + 1 { next }
			/^[A-Za-z][A-Za-z0-9-]*: / { next }   # trailers (Nightshift-Task:, etc.)
			$0 ~ /^[[:space:]]*$/ { next }
			NF == 1 { next }                       # unbreakable tokens such as URLs
			length($0) > max { print NR; exit }
		'
	)
	if [ -n "$long" ]; then
		add_error "body line $long exceeds $MAX_BODY characters; wrap the body at 72"
	fi
fi

if [ -n "$errors" ]; then
	{
		echo "commit-msg: rejected commit message"
		echo ""
		echo "  subject: $subject"
		echo ""
		printf '%s' "$errors"
		echo ""
		echo "  expected: <type>(<optional scope>): <lowercase imperative subject>"
		echo "  see $DOC_URL"
		echo ""
		echo "  bypass with --no-verify if you are certain."
	} >&2
	exit 1
fi

exit 0
