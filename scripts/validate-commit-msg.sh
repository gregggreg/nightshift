#!/usr/bin/env sh
#
# validate-commit-msg.sh — check a commit message against the repo's
# Conventional Commits format. Reports every problem it finds, not just the
# first, and suggests a corrected subject where one can be derived.
#
#   usage: scripts/validate-commit-msg.sh [--quiet] [<file>|-]
#
# Reads stdin when the file is "-" or omitted. Exits 0 when the message is
# acceptable, 1 when it is not, 2 on usage errors.
set -u

TYPES="feat fix docs style refactor perf test build ci chore revert"
MAX_SUBJECT=72
QUIET=0
SOURCE="-"

while [ $# -gt 0 ]; do
	case "$1" in
	--quiet | -q)
		QUIET=1
		;;
	-h | --help)
		sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	-)
		SOURCE="-"
		;;
	-*)
		echo "validate-commit-msg: unknown option: $1" >&2
		exit 2
		;;
	*)
		SOURCE=$1
		;;
	esac
	shift
done

if [ "$SOURCE" = "-" ]; then
	raw=$(cat)
else
	if [ ! -f "$SOURCE" ]; then
		echo "validate-commit-msg: no such file: $SOURCE" >&2
		exit 2
	fi
	raw=$(cat "$SOURCE")
fi

# Only the trailing run of blank/comment lines is treated as git's generated
# template and ignored. Anything above it -- including a body line that merely
# starts with the comment character -- is real content that git keeps under
# `git commit -m`, so it has to be validated rather than quietly discarded.
comment_prefix() {
	_cc=$(git config --get core.commentString 2>/dev/null) || _cc=""
	[ -n "$_cc" ] || { _cc=$(git config --get core.commentChar 2>/dev/null) || _cc=""; }
	case "$_cc" in
	"" | auto) printf '#' ;;
	*) printf '%s' "$_cc" ;;
	esac
}

message=$(printf '%s\n' "$raw" | awk -v cc="$(comment_prefix)" '
	{ sub(/[ \t\r]+$/, ""); line[NR] = $0 }
	END {
		i = NR
		found = 0
		while (i >= 1) {
			if (line[i] == "") { i--; continue }
			if (substr(line[i], 1, length(cc)) == cc) { found = 1; i--; continue }
			break
		}
		last = found ? i : NR
		for (j = 1; j <= last; j++) {
			if (!emitted && line[j] == "") continue
			emitted = 1
			print line[j]
		}
	}
')

# A message that is nothing but a template is git's problem, not ours: it
# aborts the commit with its own message.
[ -n "$message" ] || exit 0

subject=$(printf '%s\n' "$message" | sed -n '1p')
second_line=$(printf '%s\n' "$message" | sed -n '2p')

# Messages git generates or that reference another commit are exempt.
case "$subject" in
Merge\ * | Revert\ * | fixup!* | squash!* | amend!*)
	exit 0
	;;
esac

ERRORS=""
add_error() {
	ERRORS="${ERRORS}  - $1
"
}

type_pattern=$(printf '%s' "$TYPES" | tr ' ' '|')

if [ -z "$subject" ]; then
	add_error "the commit subject is empty"
else
	if printf '%s' "$subject" | grep -Eq "^($type_pattern)(\([^()]+\))?!?:[[:space:]]*$"; then
		add_error "the commit subject is empty after the type prefix"
	elif ! printf '%s' "$subject" | grep -Eq "^($type_pattern)(\([^()]+\))?!?: .+"; then
		if printf '%s' "$subject" | grep -Eq "^[A-Za-z]+(\([^()]+\))?!?:"; then
			bad_type=$(printf '%s' "$subject" | sed -E 's/^([A-Za-z]+).*/\1/')
			add_error "unknown commit type '$bad_type'; use one of: $TYPES"
		else
			add_error "the subject must start with a type, e.g. 'fix(scope): do the thing'; allowed types: $TYPES"
		fi
	else
		desc=${subject#*: }
		case "$subject" in
		*.)
			add_error "the subject must not end with a period"
			;;
		esac
		first_word=${desc%% *}
		case "$(printf '%s' "$first_word" | cut -c2-)" in
		*[A-Z]*) ;;
		*)
			case "$first_word" in
			[A-Z]*)
				add_error "use a lowercase imperative subject (write 'add x', not 'Add x')"
				;;
			esac
			;;
		esac
	fi

	# Count characters, not bytes: dropping UTF-8 continuation bytes (0x80-0xBF)
	# leaves exactly one byte per character, which `wc -c` can then count
	# regardless of the caller's locale.
	length=$(printf '%s' "$subject" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' ')
	if [ "$length" -gt "$MAX_SUBJECT" ]; then
		add_error "the subject is $length characters; keep it to $MAX_SUBJECT or fewer"
	fi
fi

if [ -n "$second_line" ]; then
	add_error "leave a blank line between the subject and the body"
fi

[ -z "$ERRORS" ] && exit 0

if [ "$QUIET" -eq 0 ]; then
	{
		echo "✗ commit message does not follow the project format:"
		echo ""
		echo "    $subject"
		echo ""
		printf '%s' "$ERRORS"
		echo ""
		suggestion=""
		normalizer="$(dirname "$0")/normalize-commit-msg.sh"
		if [ -x "$normalizer" ]; then
			tmp=$(mktemp 2>/dev/null || echo "/tmp/validate-commit-msg.$$")
			printf '%s\n' "$message" >"$tmp"
			"$normalizer" "$tmp" >/dev/null 2>&1 || true
			candidate=$(sed -n '1p' "$tmp")
			rm -f "$tmp"
			if [ -n "$candidate" ] && [ "$candidate" != "$subject" ] &&
				printf '%s' "$candidate" | grep -Eq "^($type_pattern)(\([^()]+\))?!?: .+"; then
				suggestion=$candidate
			fi
		fi
		if [ -n "$suggestion" ]; then
			echo "  try:  $suggestion"
		else
			echo "  format:  <type>(<optional scope>)<optional !>: <lowercase imperative subject>"
			echo "  example: fix(runner): stop leaking the task context"
		fi
		echo ""
		echo "  See CONTRIBUTING.md. Install the hook with: make install-hooks"
	} >&2
fi
exit 1
