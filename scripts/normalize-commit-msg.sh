#!/usr/bin/env sh
# Normalize a commit message file in place toward the Conventional Commits
# standard documented in docs/commit-messages.md.
#
# Usage: scripts/normalize-commit-msg.sh <commit-msg-file>
#
# The normalizer is conservative by design. It only applies mechanical fixes it
# can make with certainty:
#
#   - strips trailing whitespace and trailing periods from the subject
#   - lowercases a known type token ("Fix:" -> "fix:")
#   - normalizes spacing after the colon ("fix:add x" -> "fix: add x")
#   - lowercases the first word of the description when it is a known
#     imperative verb ("fix: Add x" -> "fix: add x")
#   - ensures exactly one blank line between the subject and the body
#
# It never touches the body or trailers, never edits merge/revert/fixup/squash
# commits, and leaves anything it cannot parse confidently alone so the
# validator can report a precise error instead. Exit status is 0 whenever the
# file is readable, whether or not anything changed.
set -eu

# Resolve $0 through any symlinks so the script finds its siblings when it is
# installed as .git/hooks/commit-msg.
cm_self=$0
while [ -L "$cm_self" ]; do
	cm_link=$(readlink "$cm_self")
	case "$cm_link" in
	/*) cm_self=$cm_link ;;
	*) cm_self=$(dirname -- "$cm_self")/$cm_link ;;
	esac
done
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$cm_self")" && pwd)
# shellcheck source=scripts/commit-msg-lib.sh
. "$SCRIPT_DIR/commit-msg-lib.sh"

MSG_FILE=${1:-}
if [ -z "$MSG_FILE" ]; then
	echo "usage: $(basename "$0") <commit-msg-file>" >&2
	exit 2
fi
if [ ! -f "$MSG_FILE" ]; then
	echo "$(basename "$0"): no such file: $MSG_FILE" >&2
	exit 2
fi

COMMENT_CHAR=$(cm_comment_char)
SUBJECT_LINE=$(cm_subject_lineno "$MSG_FILE" "$COMMENT_CHAR")

# Nothing to normalize: empty message, or comments only.
[ "$SUBJECT_LINE" -eq 0 ] && exit 0

subject=$(sed -n "${SUBJECT_LINE}p" "$MSG_FILE")

# Leave git's own generated commits untouched.
cm_is_exempt "$subject" && exit 0

original_subject=$subject

# 1. Trailing whitespace.
subject=$(printf '%s' "$subject" | sed 's/[[:space:]]*$//')

# 2. Trailing periods. Ellipses are stripped too; a subject ending in a period
#    carries no meaning the description does not already carry.
while :; do
	case "$subject" in
	*.) subject=${subject%.} ;;
	*) break ;;
	esac
done

# 3..5 only apply when the subject confidently parses as `type(scope)!: desc`.
if cm_has_type_prefix "$subject"; then
	prefix=${subject%%:*}
	desc=${subject#*:}

	# 3. Lowercase the type token, preserving any scope and the `!` marker.
	type=$(cm_type_of "$subject")
	scope=""
	case "$prefix" in
	*\(*\)*) scope=$(printf '%s' "$prefix" | sed -n 's/^[^(]*\(([^()]*)\).*$/\1/p') ;;
	esac
	bang=""
	case "$prefix" in
	*!) bang="!" ;;
	esac
	prefix="${type}${scope}${bang}"

	# 4. Exactly one space after the colon.
	while :; do
		case "$desc" in
		" "* | "	"*) desc=${desc#?} ;;
		*) break ;;
		esac
	done

	# 5. Lowercase a capitalized leading imperative verb, and only that.
	first_word=${desc%% *}
	if printf '%s' "$first_word" | grep -Eq '^[A-Z][a-z]+$'; then
		lowered=$(printf '%s' "$first_word" | tr '[:upper:]' '[:lower:]')
		if cm_is_known_verb "$lowered"; then
			desc="${lowered}${desc#"$first_word"}"
		fi
	fi

	if [ -n "$desc" ]; then
		subject="${prefix}: ${desc}"
	fi
fi

# Rewrite the file only when something actually changed, so an already
# conforming message keeps its exact bytes (including mtime-sensitive tooling
# behaviour downstream).
blank_run=$(awk -v start="$((SUBJECT_LINE + 1))" '
	NR < start { next }
	{
		stripped = $0
		gsub(/^[ \t]+|[ \t]+$/, "", stripped)
		if (stripped != "") exit
		n++
	}
	END { print n + 0 }
' "$MSG_FILE")
has_body=$(awk -v start="$((SUBJECT_LINE + 1))" '
	NR < start { next }
	{
		stripped = $0
		gsub(/^[ \t]+|[ \t]+$/, "", stripped)
		if (stripped != "") { print 1; found = 1; exit }
	}
	END { if (!found) print 0 }
' "$MSG_FILE")

# 6. Exactly one blank line between subject and body. Body content, including
#    interior blank lines and trailers, is copied through verbatim.
want_blank=0
if [ "$has_body" -eq 1 ]; then
	want_blank=1
fi

if [ "$subject" = "$original_subject" ] && [ "$blank_run" -eq "$want_blank" ]; then
	exit 0
fi

tmp="${MSG_FILE}.normalized.$$"
{
	if [ "$SUBJECT_LINE" -gt 1 ]; then
		sed -n "1,$((SUBJECT_LINE - 1))p" "$MSG_FILE"
	fi
	printf '%s\n' "$subject"
	if [ "$want_blank" -eq 1 ]; then
		printf '\n'
	fi
	rest_start=$((SUBJECT_LINE + 1 + blank_run))
	sed -n "${rest_start},\$p" "$MSG_FILE"
} >"$tmp"

# Preserve the original file rather than replacing it, so git's own file handle
# and any permissions/ownership on the message file survive.
cat "$tmp" >"$MSG_FILE"
rm -f "$tmp"
