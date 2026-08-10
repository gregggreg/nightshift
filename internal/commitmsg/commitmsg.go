// Package commitmsg implements the nightshift commit message standard: a
// Conventional Commits variant documented in docs/commit-messages.md.
//
// It provides two operations used by the commit-msg hook and by CI:
//
//   - Normalize rewrites a message into canonical form without changing intent.
//     It is idempotent: Normalize(Normalize(x)) == Normalize(x).
//   - Lint reports the violations that Normalize cannot fix on its own, with a
//     specific, actionable message per violation.
package commitmsg

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
	"unicode"
)

// Limits for the standard, measured in runes.
//
// Bodies should be wrapped at WrapBodyAt; MaxBodyLineLen is the hard limit the
// linter enforces. The slack between the two keeps the rule from rejecting the
// many otherwise-good commits already in this repository's history.
const (
	MaxSubjectLen  = 72
	WrapBodyAt     = 72
	MaxBodyLineLen = 80
)

// Types are the allowed commit types, mapped to a one-line meaning. The same
// table is rendered in docs/commit-messages.md.
var Types = map[string]string{
	"feat":     "a user-visible feature",
	"fix":      "a bug fix",
	"docs":     "documentation only",
	"style":    "formatting only, no behaviour change",
	"refactor": "restructuring without behaviour change",
	"perf":     "a performance improvement",
	"test":     "adding or fixing tests",
	"build":    "build system, dependencies, release packaging",
	"ci":       "CI configuration and workflows",
	"chore":    "maintenance that fits nowhere else",
	"revert":   "reverts a previous commit",
}

// TypeList returns the allowed types in a stable, alphabetical order.
func TypeList() []string {
	out := make([]string, 0, len(Types))
	for t := range Types {
		out = append(out, t)
	}
	sort.Strings(out)
	return out
}

var (
	// subjectRe matches "type(scope)!: description". Scope and "!" are optional.
	subjectRe = regexp.MustCompile(`^([A-Za-z]+)(\(([^()]*)\))?(!)?: (.*)$`)
	// looseColonRe matches anything that at least looks like it is trying to be
	// a conventional subject, so we can produce a targeted error.
	looseColonRe = regexp.MustCompile(`^([A-Za-z]+)(\(([^()]*)\))?(!)?:(.*)$`)
	// trailerRe matches a line shaped like a trailer, e.g. "Nightshift-Task: foo".
	// Matching the shape is not enough to call a line a trailer: ordinary prose
	// produces lines like "Before: 2.1s." too. See isTrailerLine.
	trailerRe = regexp.MustCompile(`^([A-Za-z][A-Za-z0-9-]*|BREAKING CHANGE): .+$`)
	// scissorsRe matches git's --verbose cut line; everything below it is a diff.
	scissorsRe = regexp.MustCompile(`^#* *-+ >8 -+`)
	// fixupRe matches messages git itself will rewrite during an autosquash.
	fixupRe = regexp.MustCompile(`^(fixup|squash|amend)! `)
	// revertRe matches git's default revert subject.
	revertRe = regexp.MustCompile(`^Revert "`)
	// mergeRe matches git's default merge subject.
	mergeRe = regexp.MustCompile(`^Merge `)
)

// knownTrailerKeys are the trailer keys this project recognizes by name,
// lowercased for case-insensitive lookup. A trailing block is only treated as a
// trailer block when at least one of its lines uses one of these keys, which is
// what keeps a body paragraph ending in "Note: …" or "Before: 2.1s." from being
// mistaken for trailers. Keys containing a hyphen ("Reviewed-by") are also
// accepted inside a block anchored by a known key, since prose never has that
// shape; see isTrailerLine.
var knownTrailerKeys = map[string]bool{
	"acked-by":        true,
	"breaking change": true,
	"bug":             true,
	"cc":              true,
	"change-id":       true,
	"closes":          true,
	"co-authored-by":  true,
	"fixes":           true,
	"helped-by":       true,
	"link":            true,
	"reported-by":     true,
	"resolves":        true,
	"reviewed-by":     true,
	"refs":            true,
	"signed-off-by":   true,
	"suggested-by":    true,
	"tested-by":       true,
}

// trailerKey returns the key of a trailer-shaped line, lowercased, and whether
// the line is trailer-shaped at all.
func trailerKey(line string) (string, bool) {
	m := trailerRe.FindStringSubmatch(line)
	if m == nil {
		return "", false
	}
	return strings.ToLower(m[1]), true
}

// isKnownTrailer reports whether the line names a trailer key this project
// recognizes, or a Nightshift-* trailer.
func isKnownTrailer(line string) bool {
	key, ok := trailerKey(line)
	if !ok {
		return false
	}
	return knownTrailerKeys[key] || strings.HasPrefix(key, "nightshift-")
}

// isTrailerLine reports whether the line may appear inside a trailer block. A
// hyphenated key is accepted on shape alone; a single-word key must be one we
// know, so prose such as "Note: be careful" is not swallowed.
func isTrailerLine(line string) bool {
	key, ok := trailerKey(line)
	if !ok {
		return false
	}
	return strings.Contains(key, "-") || knownTrailerKeys[key]
}

// Issue is a single lint violation.
type Issue struct {
	Line int    // 1-based line within the message, or 0 when not line-specific
	Rule string // stable identifier, e.g. "subject-too-long"
	Msg  string // actionable, human-readable description
}

func (i Issue) String() string {
	if i.Line > 0 {
		return fmt.Sprintf("line %d: %s (%s)", i.Line, i.Msg, i.Rule)
	}
	return fmt.Sprintf("%s (%s)", i.Msg, i.Rule)
}

// Exempt reports whether a message is one git generates or rewrites itself, and
// which therefore is not held to the standard.
func Exempt(msg string) bool {
	subject := firstLine(msg)
	return subject == "" ||
		fixupRe.MatchString(subject) ||
		revertRe.MatchString(subject) ||
		mergeRe.MatchString(subject)
}

func firstLine(msg string) string {
	for _, line := range strings.Split(msg, "\n") {
		line = strings.TrimSpace(line)
		if line != "" && !strings.HasPrefix(line, "#") {
			return line
		}
	}
	return ""
}

// Normalize rewrites raw into canonical form. It never reflows or rewraps text,
// so prose, code fences and trailers survive untouched; it only fixes the
// mechanical parts of the format. The result always ends in a single newline
// (or is empty, when the message had no content at all).
func Normalize(raw string) string {
	lines := stripComments(raw)
	lines = trimTrailingWS(lines)
	lines = collapseBlanks(lines)
	if len(lines) == 0 {
		return ""
	}

	if !Exempt(strings.Join(lines, "\n")) {
		lines[0] = normalizeSubject(lines[0])
	}

	// Ensure exactly one blank line between the subject and the body.
	if len(lines) > 1 && lines[1] != "" {
		rest := append([]string{""}, lines[1:]...)
		lines = append(lines[:1], rest...)
	}

	// Ensure a blank line before the trailer block.
	if start := trailerStart(lines); start > 1 && lines[start-1] != "" {
		rest := append([]string{""}, lines[start:]...)
		lines = append(lines[:start], rest...)
	}

	return strings.Join(lines, "\n") + "\n"
}

// stripComments drops git comment lines and everything below the --verbose
// scissors marker.
func stripComments(raw string) []string {
	raw = strings.ReplaceAll(raw, "\r\n", "\n")
	var out []string
	for _, line := range strings.Split(raw, "\n") {
		if scissorsRe.MatchString(line) {
			break
		}
		if strings.HasPrefix(line, "#") {
			continue
		}
		out = append(out, line)
	}
	return out
}

func trimTrailingWS(lines []string) []string {
	out := make([]string, len(lines))
	for i, line := range lines {
		out[i] = strings.TrimRight(line, " \t")
	}
	return out
}

// collapseBlanks removes leading and trailing blank lines and squeezes runs of
// blank lines down to one, except inside fenced code blocks.
func collapseBlanks(lines []string) []string {
	var out []string
	inFence := false
	prevBlank := false
	for _, line := range lines {
		if isFence(line) {
			inFence = !inFence
		}
		if !inFence && line == "" {
			if len(out) == 0 || prevBlank {
				continue
			}
			prevBlank = true
			out = append(out, line)
			continue
		}
		prevBlank = false
		out = append(out, line)
	}
	for len(out) > 0 && out[len(out)-1] == "" {
		out = out[:len(out)-1]
	}
	return out
}

func isFence(line string) bool {
	return strings.HasPrefix(strings.TrimSpace(line), "```")
}

// normalizeSubject trims the subject, collapses internal whitespace, removes
// trailing periods and lowercases the first word of the description when doing
// so is unambiguously safe.
func normalizeSubject(subject string) string {
	subject = strings.Join(strings.Fields(subject), " ")
	if subject == "" {
		return ""
	}

	m := subjectRe.FindStringSubmatch(subject)
	if m == nil {
		if lm := looseColonRe.FindStringSubmatch(subject); lm != nil {
			// "feat:no space" -> "feat: no space"
			m = lm
			m[5] = strings.TrimSpace(m[5])
		} else {
			// Not conventional at all; Lint reports it. Still drop trailing dots.
			return trimTrailingPeriod(subject)
		}
	}

	typ, scope, bang, desc := strings.ToLower(m[1]), m[3], m[4], m[5]
	desc = trimTrailingPeriod(strings.TrimSpace(desc))
	desc = lowerFirstWord(desc)

	prefix := typ
	if m[2] != "" {
		prefix += "(" + strings.TrimSpace(scope) + ")"
	}
	return prefix + bang + ": " + desc
}

func trimTrailingPeriod(s string) string {
	for strings.HasSuffix(s, ".") {
		s = strings.TrimSuffix(s, ".")
		s = strings.TrimRight(s, " \t")
	}
	return s
}

// lowerFirstWord lowercases the first character of the description, but leaves
// acronyms ("API"), identifiers ("GoModule") and qualified names ("README.md")
// alone.
func lowerFirstWord(desc string) string {
	if desc == "" {
		return desc
	}
	word := desc
	if i := strings.IndexAny(desc, " \t"); i >= 0 {
		word = desc[:i]
	}
	runes := []rune(word)
	if !unicode.IsUpper(runes[0]) {
		return desc
	}
	if strings.ContainsAny(word, "./_-") {
		return desc
	}
	for _, r := range runes[1:] {
		if unicode.IsUpper(r) {
			return desc // acronym or CamelCase identifier
		}
	}
	runes[0] = unicode.ToLower(runes[0])
	return string(runes) + desc[len(word):]
}

// trailerStart returns the index of the first line of the trailing trailer
// block, or -1 when the message has no trailer block. The trailer block is the
// longest run of trailer (and continuation) lines at the end of the message,
// and it only counts as one when at least one of those lines uses a key we
// recognize. Requiring a known key is what stops a body paragraph whose last
// lines happen to read "Before: 2.1s." from being treated as trailers and split
// off with a blank line. The subject line is never treated as a trailer, even
// though it looks like one.
func trailerStart(lines []string) int {
	end := len(lines)
	for end > 0 && lines[end-1] == "" {
		end--
	}
	start := end
	sawKnown := false
	for start > 1 && lines[start-1] != "" {
		line := lines[start-1]
		switch {
		case isTrailerLine(line):
			sawKnown = sawKnown || isKnownTrailer(line)
		case strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t"):
			// continuation of the trailer above it
		default:
			// A non-trailer line ends the block.
			if sawKnown {
				return start
			}
			return -1
		}
		start--
	}
	if !sawKnown || start == 0 {
		return -1
	}
	return start
}

// Lint validates a message against the standard and returns every violation it
// finds. An empty result means the message is valid.
func Lint(msg string) []Issue {
	lines := trimTrailingWS(stripComments(msg))
	for len(lines) > 0 && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	if len(lines) == 0 || strings.TrimSpace(strings.Join(lines, "")) == "" {
		return []Issue{{Rule: "empty-message", Msg: "commit message is empty"}}
	}
	if Exempt(strings.Join(lines, "\n")) {
		return nil
	}

	issues := lintSubject(lines[0])
	if len(lines) > 1 && lines[1] != "" {
		issues = append(issues, Issue{
			Line: 2,
			Rule: "missing-blank-line",
			Msg:  "the subject must be followed by a blank line before the body",
		})
	}
	issues = append(issues, lintBody(lines)...)
	return issues
}

func lintSubject(subject string) []Issue {
	var issues []Issue

	if strings.TrimSpace(subject) != subject {
		issues = append(issues, Issue{
			Line: 1, Rule: "subject-whitespace",
			Msg: "the subject has leading or trailing whitespace",
		})
		subject = strings.TrimSpace(subject)
	}

	m := subjectRe.FindStringSubmatch(subject)
	if m == nil {
		if lm := looseColonRe.FindStringSubmatch(subject); lm != nil {
			if strings.TrimSpace(lm[5]) != "" {
				issues = append(issues, Issue{
					Line: 1, Rule: "missing-space-after-colon",
					Msg: fmt.Sprintf("the subject needs a space after the colon: %q", lm[1]+lm[2]+lm[4]+": "+strings.TrimSpace(lm[5])),
				})
			}
			m = lm
			m[5] = strings.TrimSpace(m[5])
		} else {
			return append(issues, Issue{
				Line: 1, Rule: "missing-type",
				Msg: fmt.Sprintf("the subject must start with %q or %q; allowed types: %s",
					"type: ", "type(scope): ", strings.Join(TypeList(), ", ")),
			})
		}
	}

	typ, scopeGroup, scope, desc := m[1], m[2], m[3], m[5]
	if _, ok := Types[typ]; !ok {
		issues = append(issues, Issue{
			Line: 1, Rule: "unknown-type",
			Msg: fmt.Sprintf("%q is not an allowed type; use one of: %s", typ, strings.Join(TypeList(), ", ")),
		})
	}
	if scopeGroup != "" && strings.TrimSpace(scope) == "" {
		issues = append(issues, Issue{
			Line: 1, Rule: "empty-scope",
			Msg: "the scope is empty; write \"type: subject\" or give the scope a name",
		})
	}
	if strings.TrimSpace(desc) == "" {
		issues = append(issues, Issue{
			Line: 1, Rule: "empty-subject",
			Msg: "the subject text after the type is empty",
		})
		return issues
	}
	if n := len([]rune(subject)); n > MaxSubjectLen {
		issues = append(issues, Issue{
			Line: 1, Rule: "subject-too-long",
			Msg: fmt.Sprintf("the subject is %d characters; the limit is %d", n, MaxSubjectLen),
		})
	}
	if strings.HasSuffix(desc, ".") {
		issues = append(issues, Issue{
			Line: 1, Rule: "subject-trailing-period",
			Msg: "the subject must not end with a period",
		})
	}
	if first := []rune(desc)[0]; unicode.IsUpper(first) && lowerFirstWord(desc) != desc {
		issues = append(issues, Issue{
			Line: 1, Rule: "subject-capitalized",
			Msg: "the subject must start with a lowercase word (acronyms and identifiers are fine)",
		})
	}
	return issues
}

func lintBody(lines []string) []Issue {
	var issues []Issue
	trailerAt := trailerStart(lines)
	inFence := false
	for i := 1; i < len(lines); i++ {
		line := lines[i]
		if isFence(line) {
			inFence = !inFence
			continue
		}
		if inFence || (trailerAt >= 0 && i >= trailerAt) {
			continue
		}
		if strings.HasPrefix(line, "    ") || strings.HasPrefix(line, "\t") {
			continue // indented code block
		}
		if len([]rune(line)) <= MaxBodyLineLen {
			continue
		}
		// A line holding a token that is itself over the limit (a long URL or
		// path) cannot be wrapped, so it is allowed.
		if hasUnwrappableWord(line, MaxBodyLineLen) {
			continue
		}
		issues = append(issues, Issue{
			Line: i + 1, Rule: "body-line-too-long",
			Msg: fmt.Sprintf("the body line is %d characters; wrap the body at %d (hard limit %d)",
				len([]rune(line)), WrapBodyAt, MaxBodyLineLen),
		})
	}
	return issues
}

// hasUnwrappableWord reports whether the line contains a single word longer
// than n runes, which makes wrapping the line at n impossible.
func hasUnwrappableWord(line string, n int) bool {
	for _, word := range strings.Fields(line) {
		if len([]rune(word)) > n {
			return true
		}
	}
	return false
}
