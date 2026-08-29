package commitmsg

import (
	"fmt"
	"strings"
)

// The tunable limits of the format. These are the single source of truth for
// the validator, the CLI, the git hook and the agent prompts.
const (
	// MaxSubjectLen caps the whole header line, "type(scope): subject".
	MaxSubjectLen = 72
	// WrapBody is the column body paragraphs are wrapped at.
	WrapBody = 72

	// TaskTrailerKey identifies the Nightshift task a commit came from.
	TaskTrailerKey = "Nightshift-Task"
	// RefTrailerKey points back at the Nightshift project.
	RefTrailerKey = "Nightshift-Ref"
	// RefTrailerValue is the canonical value for RefTrailerKey.
	RefTrailerValue = "https://github.com/marcus/nightshift"
)

// AllowedTypes are the commit types this repository accepts.
var AllowedTypes = []string{
	"feat",
	"fix",
	"docs",
	"style",
	"refactor",
	"perf",
	"test",
	"build",
	"ci",
	"chore",
	"revert",
}

// NightshiftTrailers returns the trailers an autonomous run must attach to
// every commit it makes for the given task type.
func NightshiftTrailers(taskType string) []Trailer {
	return []Trailer{
		{Key: TaskTrailerKey, Value: taskType},
		{Key: RefTrailerKey, Value: RefTrailerValue},
	}
}

// Spec returns the canonical, human-readable description of the commit
// message format. Everything that explains the format — `nightshift
// commit-msg --print-spec`, the commit-msg hook's failure output, the docs
// and the agent prompts — quotes this text.
func Spec() string {
	return fmt.Sprintf(`Commit message format

  type(scope)!: subject
  <blank line>
  body, wrapped at %d columns
  <blank line>
  Trailer-Key: value

Rules
  - type is required and lowercase, one of: %s
  - scope is optional and describes the area touched, e.g. (cli), (db)
  - "!" after the type/scope marks a breaking change
  - the whole header line "type(scope): subject" is at most %d characters
  - the subject is imperative mood ("add x", not "added x") and has no
    trailing period
  - a blank line separates the subject from the body and the body from the
    trailers
  - body paragraphs wrap at %d columns; code blocks, indented text, lists
    and URLs are left alone
  - trailers form one block at the very end, one "Key: value" per line

Example
  feat(cli): add commit message normalizer

  Adds a nightshift commit-msg subcommand that checks and rewrites commit
  messages so every commit in the repository shares one format.

  Nightshift-Task: commit-normalize
  Nightshift-Ref: %s
`, WrapBody, strings.Join(AllowedTypes, ", "), MaxSubjectLen, WrapBody, RefTrailerValue)
}

// PromptSpec returns the commit instructions handed to autonomous agents for
// a task of the given type: the shared Spec plus the exact trailers the run
// must attach. It is the same format `nightshift commit-msg --check`
// enforces, so agents are told precisely what the hook will accept.
func PromptSpec(taskType string) string {
	var b strings.Builder
	for _, line := range strings.Split(strings.TrimRight(Spec(), "\n"), "\n") {
		if line == "" {
			b.WriteString("\n")
			continue
		}
		b.WriteString("   " + line + "\n")
	}
	b.WriteString("\n   Every commit you make must also carry these trailers:\n")
	for _, t := range NightshiftTrailers(taskType) {
		b.WriteString("   " + t.String() + "\n")
	}
	return strings.TrimRight(b.String(), "\n")
}
