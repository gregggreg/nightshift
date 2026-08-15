#!/usr/bin/env sh
# Shared helpers for the commit message normalizer and validator.
# POSIX sh, no external dependencies beyond awk/sed/tr and git.
# shellcheck shell=sh

# Allowed Conventional Commits types. Derived from the types this repo's own
# history already uses (feat, fix, docs, chore, test, refactor) plus the
# remaining standard set so the vocabulary is not artificially narrow.
CM_TYPES="build chore ci docs feat fix perf refactor revert style test"

# Maximum subject length, matching the git convention of a short summary that
# survives `git log --oneline` and GitHub's UI without truncation.
CM_MAX_SUBJECT=72

# Imperative verbs the normalizer is willing to lowercase automatically.
# Deliberately an allowlist: lowercasing anything else risks mangling a proper
# noun ("Nightshift", "GitHub", "API") that is legitimately capitalized.
CM_VERBS="add allow apply avoid bump clean correct document drop ensure \
fix guard handle harden ignore improve make move prevent refactor remove \
rename replace restore skip stop support switch update use verify wire"

# Print the effective git comment character (default '#').
cm_comment_char() {
	cc=$(git config --get core.commentChar 2>/dev/null || true)
	if [ -z "$cc" ] || [ "$cc" = "auto" ]; then
		cc='#'
	fi
	printf '%s' "$cc"
}

# Print the 1-based line number of the subject line in a commit message file,
# or 0 if the message has no subject (empty or comments only).
# Usage: cm_subject_lineno <file> <comment_char>
cm_subject_lineno() {
	awk -v c="$2" '
		{
			if (substr($0, 1, 1) == c) next
			stripped = $0
			gsub(/^[ \t]+|[ \t]+$/, "", stripped)
			if (stripped == "") next
			print NR
			found = 1
			exit
		}
		END { if (!found) print 0 }
	' "$1"
}

# True when the subject belongs to a commit git generates or rewrites itself.
# These are exempt from both normalization and validation.
cm_is_exempt() {
	case "$1" in
	"Merge "* | "Revert \""* | "fixup! "* | "squash! "* | "amend! "*) return 0 ;;
	esac
	return 1
}

# True when the subject starts with a well-formed `type`, `type(scope)`,
# `type!` or `type(scope)!` prefix followed by a colon. Case-insensitive on the
# type so the normalizer can repair "Fix: ..." before validation runs.
cm_has_type_prefix() {
	case "$1" in
	*:*) ;;
	*) return 1 ;;
	esac
	prefix=${1%%:*}
	printf '%s' "$prefix" | grep -Eq '^[A-Za-z]+(\([^()]+\))?!?$' || return 1
	t=$(cm_type_of "$1")
	cm_is_known_type "$t"
}

# Print the lowercased type token of a subject with a `type...:` prefix.
cm_type_of() {
	prefix=${1%%:*}
	prefix=${prefix%%(*}
	prefix=${prefix%!}
	printf '%s' "$prefix" | tr '[:upper:]' '[:lower:]'
}

cm_is_known_type() {
	for t in $CM_TYPES; do
		[ "$1" = "$t" ] && return 0
	done
	return 1
}

cm_is_known_verb() {
	for v in $CM_VERBS; do
		[ "$1" = "$v" ] && return 0
	done
	return 1
}
