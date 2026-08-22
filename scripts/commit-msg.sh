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

# Limits are character counts, not byte counts: a subject with accents, an
# em-dash, smart quotes, or emoji must not get a smaller budget than an ASCII
# one. macOS awk measures length() in bytes even under a UTF-8 locale, so use
# `wc -m`, which is multibyte-aware as long as the locale is. Probe for a UTF-8
# locale this machine actually has rather than assuming a particular name.
utf8_locale=""
for candidate in "${LC_ALL:-}" "${LC_CTYPE:-}" "${LANG:-}" C.UTF-8 en_US.UTF-8; do
	[ -n "$candidate" ] || continue
	# U+00E9 is two bytes in UTF-8; a locale that reports 1 counts characters.
	if [ "$(printf '\303\251' | LC_ALL="$candidate" wc -m 2>/dev/null | tr -d ' ')" = "1" ]; then
		utf8_locale=$candidate
		break
	fi
done

# char_len <string> -- length in characters, falling back to bytes only when no
# UTF-8 locale is available at all.
char_len() {
	if [ -n "$utf8_locale" ]; then
		printf '%s' "$1" | LC_ALL="$utf8_locale" wc -m | tr -d ' '
	else
		printf '%s' "$1" | wc -c | tr -d ' '
	fi
}

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

# Strip comment lines and the scissors section git adds under --verbose,
# tagging each surviving line with its original line number so errors point at
# the line the author is looking at in their editor. `git commit` does not strip
# the comment block before running this hook, and the template installed by
# `make install-hooks` is 18 comment lines, so the two numberings differ in the
# normal workflow.
numbered=$(
	awk -v c="$comment_char" '
		index($0, "------------------------ >8 ------------------------") { exit }
		substr($0, 1, length(c)) == c { next }
		{ sub(/\r$/, ""); print NR "\t" $0 }
	' "$message_file"
)
stripped=$(printf '%s\n' "$numbered" | awk '{ print substr($0, index($0, "\t") + 1) }')

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
	length=$(char_len "$subject")
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
	# Walked in the shell rather than awk so the reported number is the original
	# file line and the measurement counts characters, not bytes.
	tab=$(printf '\t')
	line_index=0
	while IFS= read -r entry; do
		line_index=$((line_index + 1))
		[ "$line_index" -gt "$((subject_line + 1))" ] || continue

		orig_line=${entry%%"$tab"*}
		text=${entry#*"$tab"}

		# Skip blank lines.
		case "$text" in
		*[![:space:]]*) ;;
		*) continue ;;
		esac
		# Skip trailers (Nightshift-Task:, BREAKING CHANGE:, etc.).
		if printf '%s' "$text" | grep -qE '^[A-Za-z][A-Za-z0-9-]*: '; then
			continue
		fi
		# Skip unbreakable single tokens such as URLs.
		if [ "$(printf '%s\n' "$text" | awk '{ print NF }')" -le 1 ]; then
			continue
		fi

		text_length=$(char_len "$text")
		if [ "$text_length" -gt "$MAX_BODY" ]; then
			add_error "body line $orig_line is $text_length characters; keep body lines to $MAX_BODY or fewer (wrap at 72)"
			break
		fi
	done <<-BODY
	$numbered
	BODY
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
