// Package commitmsg parses, validates and normalizes git commit messages
// against a single Conventional-Commits-style format.
//
// The canonical, human-readable description of that format lives in spec.go
// so the CLI, the git hook, the docs and the agent prompts all quote one
// source of truth. This package uses the standard library only.
package commitmsg

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
	"unicode"
)

// Severity classifies how badly an issue breaks the format.
type Severity int

const (
	// SeverityWarning marks a stylistic problem that does not fail --check.
	SeverityWarning Severity = iota
	// SeverityError marks a problem that fails --check.
	SeverityError
)

// String renders the severity as a lowercase word.
func (s Severity) String() string {
	if s == SeverityError {
		return "error"
	}
	return "warning"
}

// Issue is a single validation finding.
type Issue struct {
	// Line is the 1-based line of the normalized message the issue refers to.
	// Zero means "the message as a whole".
	Line     int
	Severity Severity
	Rule     string
	Message  string
}

// String renders the issue as "line N: severity: message (rule)".
func (i Issue) String() string {
	return fmt.Sprintf("line %d: %s: %s (%s)", i.Line, i.Severity, i.Message, i.Rule)
}

// Trailer is a single git trailer, e.g. "Nightshift-Task: commit-normalize".
type Trailer struct {
	Key   string
	Value string
}

// String renders the trailer as "Key: Value".
func (t Trailer) String() string { return t.Key + ": " + t.Value }

// Message is a parsed commit message.
type Message struct {
	Type     string
	Scope    string
	Breaking bool
	Subject  string
	Body     string
	Trailers []Trailer

	// rawHeader is the header line exactly as written, used to report issues
	// about headers that do not match the conventional format at all.
	rawHeader string
	// noBlankAfterSubject records that the source message ran the body
	// straight into the subject line.
	noBlankAfterSubject bool
}

// Options controls validation and normalization.
type Options struct {
	// AllowedTypes are the accepted commit types, in canonical order.
	AllowedTypes []string
	// MaxSubjectLen caps the length of the whole header line.
	MaxSubjectLen int
	// WrapBody is the column body paragraphs are wrapped at.
	WrapBody int
	// RequiredTrailers must be present; Normalize appends missing ones.
	RequiredTrailers []Trailer
}

// DefaultOptions returns the format Nightshift enforces on itself.
func DefaultOptions() Options {
	return Options{
		AllowedTypes:  append([]string(nil), AllowedTypes...),
		MaxSubjectLen: MaxSubjectLen,
		WrapBody:      WrapBody,
	}
}

var (
	headerRe = regexp.MustCompile(`^([A-Za-z][A-Za-z0-9]*)(?:\(([^()]+)\))?(!)?:[ \t]*(.*)$`)
	// Git trailer syntax: "Token: value", token may contain letters, digits
	// and hyphens. "BREAKING CHANGE" is allowed as a special case.
	trailerRe = regexp.MustCompile(`^(BREAKING CHANGE|[A-Za-z][A-Za-z0-9-]*):[ \t]+(.*\S)[ \t]*$`)
)

// knownTrailerKeys are hoisted out of the body even when they appear in the
// middle of a message, so every message ends with one trailer block.
var knownTrailerKeys = map[string]bool{
	"nightshift-task": true,
	"nightshift-ref":  true,
	"co-authored-by":  true,
	"signed-off-by":   true,
	"reviewed-by":     true,
	"acked-by":        true,
	"tested-by":       true,
	"reported-by":     true,
	"refs":            true,
	"fixes":           true,
	"closes":          true,
	"breaking change": true,
}

// ErrEmptyMessage is returned when nothing but comments or whitespace remains.
var ErrEmptyMessage = errors.New("commit message is empty")

// Parse reads a raw commit message — including one straight out of a
// COMMIT_EDITMSG file, with git's comment lines and verbose diff attached —
// into a Message. A header that does not follow the conventional format is
// not an error: it parses with an empty Type so Validate can report it.
func Parse(raw string) (*Message, error) {
	lines := cleanLines(raw)
	if len(lines) == 0 {
		return nil, ErrEmptyMessage
	}

	m := &Message{rawHeader: lines[0]}
	if match := headerRe.FindStringSubmatch(lines[0]); match != nil {
		m.Type = match[1]
		m.Scope = match[2]
		m.Breaking = match[3] == "!"
		m.Subject = strings.TrimSpace(match[4])
	} else {
		m.Subject = strings.TrimSpace(lines[0])
	}

	rest := lines[1:]
	if len(rest) > 0 && strings.TrimSpace(rest[0]) != "" {
		m.noBlankAfterSubject = true
	}
	for len(rest) > 0 && strings.TrimSpace(rest[0]) == "" {
		rest = rest[1:]
	}

	bodyLines, trailers := splitTrailers(rest)
	m.Body = strings.Join(bodyLines, "\n")
	m.Body = strings.Trim(m.Body, "\n")
	m.Trailers = trailers
	return m, nil
}

// cleanLines strips git's comment lines and any verbose diff, and trims
// trailing whitespace and leading/trailing blank lines.
func cleanLines(raw string) []string {
	raw = strings.ReplaceAll(raw, "\r\n", "\n")
	var out []string
	for _, line := range strings.Split(raw, "\n") {
		trimmed := strings.TrimRight(line, " \t")
		// git --verbose puts an uncommented diff below a scissors line.
		if isScissors(trimmed) || strings.HasPrefix(trimmed, "diff --git ") {
			break
		}
		if strings.HasPrefix(strings.TrimSpace(trimmed), "#") {
			continue
		}
		out = append(out, trimmed)
	}
	// Trim leading and trailing blank lines.
	for len(out) > 0 && strings.TrimSpace(out[0]) == "" {
		out = out[1:]
	}
	for len(out) > 0 && strings.TrimSpace(out[len(out)-1]) == "" {
		out = out[:len(out)-1]
	}
	return out
}

func isScissors(line string) bool {
	t := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(line), "#"))
	return strings.Contains(t, ">8") && strings.Contains(t, "--")
}

// splitTrailers separates body lines from trailers. It takes the trailing
// block when it is made entirely of trailers, and additionally hoists any
// well-known trailer that got stranded in the middle of the body.
func splitTrailers(lines []string) ([]string, []Trailer) {
	var trailers []Trailer

	// Trailing block: walk back over the last contiguous non-blank run.
	end := len(lines)
	start := end
	for start > 0 && strings.TrimSpace(lines[start-1]) != "" {
		start--
	}
	if start < end {
		allTrailers := true
		for _, line := range lines[start:end] {
			if trailerRe.FindStringSubmatch(line) == nil {
				allTrailers = false
				break
			}
		}
		if allTrailers {
			for _, line := range lines[start:end] {
				match := trailerRe.FindStringSubmatch(line)
				trailers = append(trailers, Trailer{Key: match[1], Value: match[2]})
			}
			lines = lines[:start]
		}
	}

	// Hoist stranded well-known trailers, keeping document order ahead of the
	// trailing block's.
	var body []string
	var hoisted []Trailer
	for _, line := range lines {
		if match := trailerRe.FindStringSubmatch(line); match != nil && knownTrailerKeys[strings.ToLower(match[1])] {
			hoisted = append(hoisted, Trailer{Key: match[1], Value: match[2]})
			continue
		}
		body = append(body, line)
	}
	return body, append(hoisted, trailers...)
}

// Header renders just the first line of the message.
func (m *Message) Header() string {
	if m.Type == "" {
		return m.Subject
	}
	head := m.Type
	if m.Scope != "" {
		head += "(" + m.Scope + ")"
	}
	if m.Breaking {
		head += "!"
	}
	return head + ": " + m.Subject
}

// String renders the message in canonical layout, without a trailing newline.
func (m *Message) String() string {
	var b strings.Builder
	b.WriteString(m.Header())
	if body := strings.Trim(m.Body, "\n"); body != "" {
		b.WriteString("\n\n")
		b.WriteString(body)
	}
	if len(m.Trailers) > 0 {
		b.WriteString("\n\n")
		for i, t := range m.Trailers {
			if i > 0 {
				b.WriteString("\n")
			}
			b.WriteString(t.String())
		}
	}
	return b.String()
}

// Validate checks the message against DefaultOptions.
func Validate(m *Message) []Issue { return ValidateWithOptions(m, DefaultOptions()) }

// ValidateWithOptions checks the message against opts and returns every
// issue found, errors and warnings alike.
func ValidateWithOptions(m *Message, opts Options) []Issue {
	var issues []Issue
	add := func(line int, sev Severity, rule, format string, args ...interface{}) {
		issues = append(issues, Issue{Line: line, Severity: sev, Rule: rule, Message: fmt.Sprintf(format, args...)})
	}

	switch {
	case m.Type == "":
		add(1, SeverityError, "header-format",
			"header must be %q, got %q", "type(scope): subject", m.rawHeader)
	default:
		if strings.ToLower(m.Type) != m.Type {
			add(1, SeverityError, "type-lowercase", "type %q must be lowercase", m.Type)
		}
		if !allowed(strings.ToLower(m.Type), opts.AllowedTypes) {
			add(1, SeverityError, "type-allowed",
				"unknown type %q; allowed: %s", m.Type, strings.Join(opts.AllowedTypes, ", "))
		}
	}

	if strings.TrimSpace(m.Subject) == "" {
		add(1, SeverityError, "subject-empty", "subject must not be empty")
	} else {
		if n := len(m.Header()); n > opts.MaxSubjectLen {
			add(1, SeverityError, "subject-length",
				"header is %d characters, limit is %d", n, opts.MaxSubjectLen)
		}
		if strings.HasSuffix(m.Subject, ".") {
			add(1, SeverityError, "subject-trailing-period", "subject must not end with a period")
		}
		if word := firstWord(m.Subject); !isImperative(word) {
			add(1, SeverityWarning, "subject-mood",
				"subject should use the imperative mood (%q reads as past tense or third person)", word)
		}
	}

	if m.noBlankAfterSubject {
		add(2, SeverityError, "body-blank-line", "subject and body must be separated by a blank line")
	}

	for i, line := range strings.Split(m.Body, "\n") {
		if !protectedLine(line) && len(line) > opts.WrapBody {
			add(bodyLineNumber(i), SeverityWarning, "body-wrap",
				"body line is %d characters, wrap at %d", len(line), opts.WrapBody)
		}
	}

	for _, want := range opts.RequiredTrailers {
		if !hasTrailerKey(m.Trailers, want.Key) {
			add(0, SeverityError, "trailer-required", "missing required trailer %q", want.Key)
		}
	}

	return issues
}

// bodyLineNumber maps a 0-based body line index onto the rendered message,
// where line 1 is the header and line 2 is the blank separator.
func bodyLineNumber(i int) int { return i + 3 }

func allowed(t string, allowedTypes []string) bool {
	for _, a := range allowedTypes {
		if a == t {
			return true
		}
	}
	return false
}

func hasTrailerKey(trailers []Trailer, key string) bool {
	for _, t := range trailers {
		if strings.EqualFold(t.Key, key) {
			return true
		}
	}
	return false
}

// HasErrors reports whether any issue is error severity.
func HasErrors(issues []Issue) bool {
	for _, i := range issues {
		if i.Severity == SeverityError {
			return true
		}
	}
	return false
}

// Normalize rewrites raw into the canonical format, returning the normalized
// message (with a trailing newline), the issues that remain after everything
// fixable has been fixed, and an error only when the message cannot be
// normalized at all — empty, or with a subject no type can be inferred from.
func Normalize(raw string, opts Options) (string, []Issue, error) {
	m, err := Parse(raw)
	if err != nil {
		return "", nil, err
	}
	if strings.TrimSpace(m.Subject) == "" {
		return "", nil, errors.New("commit message has no subject")
	}

	if m.Type == "" {
		inferred := inferType(m.Subject)
		if inferred == "" {
			return "", nil, fmt.Errorf("cannot infer a commit type from subject %q; "+
				"prefix it explicitly, e.g. \"fix: %s\"", m.Subject, m.Subject)
		}
		m.Type = inferred
	}
	m.Type = strings.ToLower(m.Type)
	m.Subject = normalizeSubject(m.Subject)
	m.noBlankAfterSubject = false
	m.Body = wrapBody(m.Body, opts.WrapBody)
	m.Trailers = mergeTrailers(m.Trailers, opts.RequiredTrailers)

	out := m.String() + "\n"
	return out, ValidateWithOptions(m, opts), nil
}

// normalizeSubject strips trailing periods and lowercases the leading word
// unless it looks like an acronym or identifier.
func normalizeSubject(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimRight(s, ".")
	s = strings.TrimSpace(s)
	if s == "" {
		return s
	}
	word := firstWord(s)
	if isAcronymish(word) {
		return s
	}
	runes := []rune(s)
	runes[0] = unicode.ToLower(runes[0])
	return string(runes)
}

// isAcronymish reports whether a word should keep its capitalization, e.g.
// "API", "HTTPClient", "GitHub".
func isAcronymish(word string) bool {
	upper := 0
	for i, r := range word {
		if unicode.IsUpper(r) && i > 0 {
			return true
		}
		if unicode.IsUpper(r) {
			upper++
		}
	}
	// A single-letter uppercase word, or a word already lowercase.
	return upper > 0 && len([]rune(word)) == 1
}

func firstWord(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.IndexAny(s, " \t"); i >= 0 {
		return s[:i]
	}
	return s
}

// nonImperative lists common past-tense and third-person subject openers.
var nonImperative = map[string]bool{
	"fixed": true, "fixes": true, "added": true, "adds": true,
	"updated": true, "updates": true, "removed": true, "removes": true,
	"changed": true, "changes": true, "refactored": true, "refactors": true,
	"created": true, "creates": true, "implemented": true, "implements": true,
	"bumped": true, "bumps": true, "moved": true, "moves": true,
	"renamed": true, "renames": true, "documented": true, "documents": true,
	"improved": true, "improves": true, "deleted": true, "deletes": true,
	"wrote": true, "made": true, "makes": true,
}

func isImperative(word string) bool {
	w := strings.ToLower(strings.Trim(word, `"'`))
	if nonImperative[w] {
		return false
	}
	// "…ing" openers ("adding a thing") are gerunds, not imperatives.
	return !strings.HasSuffix(w, "ing")
}

// typeByVerb maps a leading verb to a commit type.
var typeByVerb = map[string]string{
	"fix": "fix", "fixed": "fix", "fixes": "fix", "resolve": "fix",
	"resolved": "fix", "correct": "fix", "corrected": "fix", "patch": "fix",
	"repair": "fix", "handle": "fix", "prevent": "fix", "guard": "fix",

	"add": "feat", "added": "feat", "adds": "feat", "create": "feat",
	"created": "feat", "implement": "feat", "implemented": "feat",
	"introduce": "feat", "introduced": "feat", "support": "feat",

	"refactor": "refactor", "refactored": "refactor", "rename": "refactor",
	"renamed": "refactor", "move": "refactor", "moved": "refactor",
	"simplify": "refactor", "simplified": "refactor", "extract": "refactor",
	"remove": "refactor", "removed": "refactor", "delete": "refactor",
	"deleted": "refactor", "drop": "refactor", "update": "refactor",
	"updated": "refactor", "change": "refactor", "changed": "refactor",

	"document": "docs", "documented": "docs", "clarify": "docs",

	"test": "test", "tested": "test", "cover": "test",

	"optimize": "perf", "optimized": "perf", "speed": "perf",

	"bump": "chore", "upgrade": "chore", "upgraded": "chore", "pin": "chore",
	"clean": "chore", "cleanup": "chore", "chore": "chore",

	"revert": "revert", "reverted": "revert",
}

// typeByKeyword maps a distinctive word anywhere in the subject to a type.
// These win over the leading verb: "Update the README" is docs, not refactor.
var typeByKeyword = []struct {
	word string
	typ  string
}{
	{"readme", "docs"},
	{"changelog", "docs"},
	{"documentation", "docs"},
	{"docs", "docs"},
	{"godoc", "docs"},
	{"typo", "docs"},
}

// inferType guesses a commit type from a free-form subject, returning "" when
// it cannot make a confident guess.
func inferType(subject string) string {
	lower := strings.ToLower(subject)
	words := strings.FieldsFunc(lower, func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsNumber(r) })
	wordSet := make(map[string]bool, len(words))
	for _, w := range words {
		wordSet[w] = true
	}

	for _, kw := range typeByKeyword {
		if wordSet[kw.word] {
			return kw.typ
		}
	}
	if len(words) > 0 {
		if t, ok := typeByVerb[words[0]]; ok {
			return t
		}
	}
	if wordSet["bug"] || wordSet["crash"] || wordSet["panic"] || wordSet["regression"] {
		return "fix"
	}
	if wordSet["test"] || wordSet["tests"] {
		return "test"
	}
	return ""
}

// mergeTrailers dedupes trailers (case-insensitively on the key, exactly on
// the value) and appends any required trailer that is missing.
func mergeTrailers(existing, required []Trailer) []Trailer {
	var out []Trailer
	seen := make(map[string]bool)
	for _, t := range existing {
		key := strings.ToLower(t.Key) + "\x00" + t.Value
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, t)
	}
	for _, want := range required {
		if !hasTrailerKey(out, want.Key) {
			out = append(out, want)
		}
	}
	return out
}

// wrapBody reflows prose paragraphs at width columns, leaving code blocks,
// indented text, lists, quotes and unbreakable lines (long URLs) alone.
func wrapBody(body string, width int) string {
	body = strings.Trim(body, "\n")
	if body == "" {
		return ""
	}
	var out []string
	var para []string
	inFence := false

	flush := func() {
		if len(para) == 0 {
			return
		}
		if paragraphProtected(para) {
			out = append(out, para...)
		} else {
			out = append(out, wrapParagraph(strings.Join(para, " "), width)...)
		}
		para = nil
	}

	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "```") {
			flush()
			inFence = !inFence
			out = append(out, line)
			continue
		}
		if inFence {
			out = append(out, line)
			continue
		}
		if strings.TrimSpace(line) == "" {
			flush()
			out = append(out, "")
			continue
		}
		para = append(para, line)
	}
	flush()

	// Collapse runs of blank lines and trim the edges.
	var collapsed []string
	for i, line := range out {
		if line == "" && i > 0 && out[i-1] == "" {
			continue
		}
		collapsed = append(collapsed, line)
	}
	return strings.Trim(strings.Join(collapsed, "\n"), "\n")
}

func paragraphProtected(para []string) bool {
	for _, line := range para {
		if protectedLine(line) {
			return true
		}
	}
	return false
}

// protectedLine reports whether a line must be preserved verbatim.
func protectedLine(line string) bool {
	if line == "" {
		return true
	}
	if strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t") {
		return true
	}
	switch line[0] {
	case '-', '*', '+', '>', '|', '#':
		return true
	}
	if strings.HasPrefix(line, "```") {
		return true
	}
	// A single unbreakable token, e.g. a long URL.
	if !strings.ContainsAny(line, " \t") {
		return true
	}
	return false
}

func wrapParagraph(text string, width int) []string {
	words := strings.Fields(text)
	if len(words) == 0 {
		return nil
	}
	var lines []string
	current := words[0]
	for _, w := range words[1:] {
		if len(current)+1+len(w) > width {
			lines = append(lines, current)
			current = w
			continue
		}
		current += " " + w
	}
	return append(lines, current)
}
