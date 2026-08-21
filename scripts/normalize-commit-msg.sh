#!/usr/bin/env sh
#
# normalize-commit-msg.sh — rewrite a commit message file into the repo's
# Conventional Commits format, fixing only what can be fixed unambiguously.
#
#   usage: scripts/normalize-commit-msg.sh <commit-msg-file>
#
# Fixes applied:
#   - strips trailing whitespace, leaving git's comment template alone
#   - collapses runs of blank lines and trims leading/trailing blanks
#   - ensures a blank line between the subject and the body
#   - rewrites near-miss prefixes: "Fix: x", "feat - x", "[feat] x", "fix:x"
#   - lowercases the type token and the first word of the description
#     (acronyms such as "API" are left alone)
#   - removes a trailing period from the subject
#
# Never touches merge, revert, fixup!, squash! or amend! messages, and never
# invents a type for a subject that does not already look conventional.
# Running it twice produces the same result as running it once.
set -eu

TYPES="feat fix docs style refactor perf test build ci chore revert"

if [ $# -ne 1 ]; then
	echo "usage: $(basename "$0") <commit-msg-file>" >&2
	exit 2
fi

MSG_FILE=$1
if [ ! -f "$MSG_FILE" ]; then
	echo "normalize-commit-msg: no such file: $MSG_FILE" >&2
	exit 2
fi

lower() {
	printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}

is_type() {
	for _t in $TYPES; do
		[ "$1" = "$_t" ] && return 0
	done
	return 1
}

# Git strips comment lines itself, after this hook runs, and only when it would
# have: an editor-authored message loses its generated template, but
# `git commit -m` uses cleanup=whitespace and keeps a body line that happens to
# start with the comment character. Deleting every such line here would
# silently drop user-authored body text, so instead the trailing run of
# blank/comment lines -- the template, when there is one -- is carved off,
# left completely untouched, and handed back to git verbatim.
comment_prefix() {
	_cc=$(git config --get core.commentString 2>/dev/null) || _cc=""
	[ -n "$_cc" ] || { _cc=$(git config --get core.commentChar 2>/dev/null) || _cc=""; }
	case "$_cc" in
	"" | auto) printf '#' ;;
	*) printf '%s' "$_cc" ;;
	esac
}

# First line of that trailing run, or one past the end when there is none.
split=$(awk -v cc="$(comment_prefix)" '
	{ line[NR] = $0 }
	END {
		i = NR
		found = 0
		while (i >= 1) {
			if (line[i] == "") { i--; continue }
			if (substr(line[i], 1, length(cc)) == cc) { found = 1; i--; continue }
			break
		}
		print found ? i + 1 : NR + 1
	}
' "$MSG_FILE")

trailing=$(sed -n "${split},\$p" "$MSG_FILE")

# Structural cleanup of everything above it: rstrip, collapse blank runs,
# trim edges.
if [ "$split" -gt 1 ]; then
	cleaned=$(sed -n "1,$((split - 1))p" "$MSG_FILE" | awk '
		{ sub(/[ \t\r]+$/, "") }
		$0 == "" { blank = 1; next }
		{
			if (emitted && blank) print ""
			blank = 0
			emitted = 1
			print
		}
	')
else
	cleaned=""
fi

# Nothing but a template (or nothing at all): leave the file exactly as it is
# and let git report the empty message.
[ -n "$cleaned" ] || exit 0

subject=$(printf '%s\n' "$cleaned" | sed -n '1p')
body=$(printf '%s\n' "$cleaned" | awk 'NR > 1 { if (!seen && $0 == "") next; seen = 1; print }')

# Messages git generates or that reference another commit are left verbatim.
case "$subject" in
Merge\ * | Revert\ * | fixup!* | squash!* | amend!*)
	exit 0
	;;
esac

# Only rewrite subjects whose leading word is already a known type; anything
# else is left for the validator to reject with an explanation.
lead=$(printf '%s' "$subject" | sed -E 's/^[[:space:]]*\[?[[:space:]]*([A-Za-z]+).*/\1/')
if is_type "$(lower "$lead")"; then
	s=$subject

	# "[feat] x" / "[feat(api)] x" -> "feat: x" / "feat(api): x"
	s=$(printf '%s' "$s" | sed -E 's/^[[:space:]]*\[[[:space:]]*([A-Za-z]+)([^]]*)\][[:space:]]*:?[[:space:]]*/\1\2: /')

	# Normalize the separator and spacing: "feat - x", "fix:x" -> "feat: x"
	s=$(printf '%s' "$s" | sed -E 's/^[[:space:]]*([A-Za-z]+)[[:space:]]*(\([^)]*\))?[[:space:]]*(!?)[[:space:]]*(:|-)[[:space:]]*/\1\2\3: /')

	# Only keep going if those two rewrites actually produced a conventional
	# subject. "Fix the bug" starts with a type word but has no separator to
	# work with, so there is nothing that can be fixed unambiguously -- leave
	# it exactly as written for the validator to reject, rather than
	# half-rewriting a message that is going to be refused anyway.
	if printf '%s' "$s" | grep -Eq '^[A-Za-z]+(\([^()]+\))?!?: .+'; then

		# Lowercase the type token.
		type_token=$(printf '%s' "$s" | sed -E 's/^([A-Za-z]+).*/\1/')
		s="$(lower "$type_token")${s#"$type_token"}"

		# Drop a trailing period.
		s=$(printf '%s' "$s" | sed -E 's/[[:space:]]*\.+$//')

		# Lowercase the first word of the description unless it looks like an
		# acronym or CamelCase identifier (API, OAuth, HTTPStatus, ...).
		case "$s" in
		*": "*)
			prefix=${s%%: *}
			desc=${s#*: }
			first_word=${desc%% *}
			case "$(printf '%s' "$first_word" | cut -c2-)" in
			*[A-Z]*) ;;
			*)
				head_char=$(printf '%s' "$desc" | cut -c1)
				desc="$(lower "$head_char")$(printf '%s' "$desc" | cut -c2-)"
				;;
			esac
			s="$prefix: $desc"
			;;
		esac

		s=$(printf '%s' "$s" | sed -E 's/[[:space:]]+$//')
		subject=$s
	fi
fi

# Trailers must be their own paragraph or git will not parse them. Only a
# trailing run of hyphenated-key lines (Co-Authored-By, Nightshift-Task, ...)
# counts, so a body ending in "Note: ..." is left alone.
if [ -n "$body" ]; then
	body=$(printf '%s\n' "$body" | awk '
		{ line[NR] = $0 }
		END {
			start = NR + 1
			while (start - 1 >= 1 && line[start - 1] ~ /^[A-Za-z][A-Za-z0-9]*(-[A-Za-z0-9]+)+: .+$/)
				start--
			if (start > 1 && start <= NR && line[start - 1] != "")
				insert = start
			for (i = 1; i <= NR; i++) {
				if (i == insert) print ""
				print line[i]
			}
		}
	')
fi

{
	if [ -n "$body" ]; then
		printf '%s\n\n%s\n' "$subject" "$body"
	else
		printf '%s\n' "$subject"
	fi
	if [ -n "$trailing" ]; then
		printf '%s\n' "$trailing"
	fi
} >"$MSG_FILE"
