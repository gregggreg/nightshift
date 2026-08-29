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
	"unicode/utf8"
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

	// GitGenerated marks a message git wrote itself — a merge, a revert, or a
	// fixup!/squash!/amend! commit. Those headers are fixed by git and are
	// exempt from every rule below.
	GitGenerated bool

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
	// Headers git generates on the user's behalf. Enforcing the conventional
	// format on these would break `git merge --no-ff` (which aborts mid-merge
	// when commit-msg fails) and every `git commit --fixup`/`--squash`, and so
	// `git rebase --autosquash`.
	//
	// The merge alternatives are spelled out rather than matching a bare
	// "Merge " prefix: git only ever writes these six, and a loose prefix
	// would let an ordinary subject like "Merge duplicate config loaders"
	// skip validation entirely.
	gitGeneratedRe = regexp.MustCompile(
		`^(Merge (branch|branches|remote-tracking branch|pull request|tag|commit) |Revert "|fixup! |squash! |amend! )`)
)

// IsGitGenerated reports whether a header line was written by git itself —
// a merge, a revert, or a fixup!/squash!/amend! commit — and is therefore
// exempt from the commit format.
func IsGitGenerated(header string) bool {
	return gitGeneratedRe.MatchString(header)
}

// knownTrailerKeys are the trailer keys this repository recognises. A
// paragraph of trailers is only treated as trailers when it uses at least one
// of these, which keeps colon-prefixed prose in the body where it belongs.
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

	m := &Message{rawHeader: lines[0], GitGenerated: IsGitGenerated(lines[0])}
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

// splitTrailers separates body lines from trailers. Trailers are only taken
// from a paragraph made entirely of trailers, or from the run of well-known
// trailers that ends the message. A trailer-shaped line in the middle of a
// prose paragraph is left alone: lifting it out would weld the surrounding
// sentences together and change what the message says.
func splitTrailers(lines []string) ([]string, []Trailer) {
	blocks := paragraphs(lines)

	var body []string
	var hoisted, tail []Trailer
	for i, block := range blocks {
		last := i == len(blocks)-1
		switch {
		case strings.TrimSpace(strings.Join(block, "")) == "":
			body = append(body, block...)
		case isTrailerBlock(block):
			if last {
				tail = append(tail, toTrailers(block)...)
			} else {
				hoisted = append(hoisted, toTrailers(block)...)
			}
		case last:
			// Prose followed by trailers: take the trailers off the end only.
			split := len(block)
			for split > 0 && isKnownTrailerLine(block[split-1]) {
				split--
			}
			body = append(body, block[:split]...)
			tail = append(tail, toTrailers(block[split:])...)
		default:
			body = append(body, block...)
		}
	}
	return trimBlankEdges(body), append(hoisted, tail...)
}

// paragraphs splits lines into alternating runs of blank and non-blank lines.
func paragraphs(lines []string) [][]string {
	var out [][]string
	var cur []string
	blank := false
	for _, line := range lines {
		isBlank := strings.TrimSpace(line) == ""
		if len(cur) > 0 && isBlank != blank {
			out = append(out, cur)
			cur = nil
		}
		blank = isBlank
		cur = append(cur, line)
	}
	if len(cur) > 0 {
		out = append(out, cur)
	}
	return out
}

// isTrailerBlock reports whether every line of a paragraph is a trailer and at
// least one uses a key we recognise. The second condition keeps a paragraph of
// colon-prefixed prose ("really: this is prose") out of the trailer block.
func isTrailerBlock(block []string) bool {
	known := false
	for _, line := range block {
		match := trailerRe.FindStringSubmatch(line)
		if match == nil {
			return false
		}
		if knownTrailerKeys[strings.ToLower(match[1])] {
			known = true
		}
	}
	return known
}

func isKnownTrailerLine(line string) bool {
	match := trailerRe.FindStringSubmatch(line)
	return match != nil && knownTrailerKeys[strings.ToLower(match[1])]
}

func toTrailers(lines []string) []Trailer {
	var out []Trailer
	for _, line := range lines {
		match := trailerRe.FindStringSubmatch(line)
		out = append(out, Trailer{Key: match[1], Value: match[2]})
	}
	return out
}

func trimBlankEdges(lines []string) []string {
	for len(lines) > 0 && strings.TrimSpace(lines[0]) == "" {
		lines = lines[1:]
	}
	for len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) == "" {
		lines = lines[:len(lines)-1]
	}
	return lines
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
	// Git writes merge, revert and fixup!/squash!/amend! headers itself; the
	// user cannot choose their format, so there is nothing to enforce.
	if m.GitGenerated {
		return nil
	}

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
		if n := utf8.RuneCountInString(m.Header()); n > opts.MaxSubjectLen {
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
		n := utf8.RuneCountInString(line)
		if !protectedLine(line) && !hasUnbreakableWord(line, opts.WrapBody) && n > opts.WrapBody {
			add(bodyLineNumber(i), SeverityWarning, "body-wrap",
				"body line is %d characters, wrap at %d", n, opts.WrapBody)
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
	if m.GitGenerated {
		// Nothing to rewrite: only git's comments and verbose diff are dropped.
		return strings.Join(cleanLines(raw), "\n") + "\n", nil, nil
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

// hasUnbreakableWord reports whether a line contains a single token longer
// than width — a URL, say. No amount of wrapping brings such a line inside
// the limit, so it is neither rewrapped nor reported.
func hasUnbreakableWord(line string, width int) bool {
	for _, w := range strings.Fields(line) {
		if utf8.RuneCountInString(w) > width {
			return true
		}
	}
	return false
}

// wrapParagraph greedily fills lines up to width characters. A word too long
// to fit on a line of its own stays on the line it started, because breaking
// before it would leave an over-limit line either way and only orphan the
// words in front of it.
func wrapParagraph(text string, width int) []string {
	words := strings.Fields(text)
	if len(words) == 0 {
		return nil
	}
	var lines []string
	current := words[0]
	for _, w := range words[1:] {
		switch {
		case current == "":
			current = w
		case utf8.RuneCountInString(current)+1+utf8.RuneCountInString(w) <= width:
			current += " " + w
		case utf8.RuneCountInString(w) > width:
			lines = append(lines, current+" "+w)
			current = ""
		default:
			lines = append(lines, current)
			current = w
		}
	}
	if current == "" {
		return lines
	}
	return append(lines, current)
}
