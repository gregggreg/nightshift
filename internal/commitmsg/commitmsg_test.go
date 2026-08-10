package commitmsg

import (
	"strings"
	"testing"
)

func TestNormalize(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{
			name: "already canonical is unchanged",
			in:   "feat(budget): add monthly rollover\n",
			want: "feat(budget): add monthly rollover\n",
		},
		{
			name: "drops trailing period and capital",
			in:   "fix: Correct the budget rollover.\n",
			want: "fix: correct the budget rollover\n",
		},
		{
			name: "drops multiple trailing periods",
			in:   "chore: tidy up the makefile...\n",
			want: "chore: tidy up the makefile\n",
		},
		{
			name: "lowercases the type",
			in:   "Fix: broken parser\n",
			want: "fix: broken parser\n",
		},
		{
			name: "inserts the space after the colon",
			in:   "docs:explain the hook\n",
			want: "docs: explain the hook\n",
		},
		{
			name: "collapses internal whitespace and trims",
			in:   "  feat(cli):   add   --timeout flag  \n",
			want: "feat(cli): add --timeout flag\n",
		},
		{
			name: "preserves acronyms",
			in:   "feat: API key rotation\n",
			want: "feat: API key rotation\n",
		},
		{
			name: "preserves identifiers with dots",
			in:   "docs: README.md gains a hook section\n",
			want: "docs: README.md gains a hook section\n",
		},
		{
			name: "preserves the breaking change marker",
			in:   "feat(config)!: Rename the provider key.\n",
			want: "feat(config)!: rename the provider key\n",
		},
		{
			name: "strips comments and the verbose diff",
			in: "fix: drop the stray log line\n" +
				"# Please enter the commit message for your changes.\n" +
				"# On branch main\n" +
				"# ------------------------ >8 ------------------------\n" +
				"diff --git a/x.go b/x.go\n",
			want: "fix: drop the stray log line\n",
		},
		{
			name: "inserts the blank line after the subject",
			in:   "fix: drop the stray log line\nIt was left over from debugging.\n",
			want: "fix: drop the stray log line\n\nIt was left over from debugging.\n",
		},
		{
			name: "squeezes repeated blank lines",
			in:   "fix: a\n\n\n\nbody text\n\n\n",
			want: "fix: a\n\nbody text\n",
		},
		{
			name: "preserves trailers verbatim",
			in: "chore: wire up the hook\n\nbody text\n" +
				"Nightshift-Task: commit-normalize\n" +
				"Nightshift-Ref: https://github.com/marcus/nightshift\n" +
				"Co-Authored-By: Someone <someone@example.com>\n",
			want: "chore: wire up the hook\n\nbody text\n\n" +
				"Nightshift-Task: commit-normalize\n" +
				"Nightshift-Ref: https://github.com/marcus/nightshift\n" +
				"Co-Authored-By: Someone <someone@example.com>\n",
		},
		{
			name: "leaves fenced code untouched",
			in:   "docs: show the hook output\n\n```\n\n  spaced   out\n\n```\n",
			want: "docs: show the hook output\n\n```\n\n  spaced   out\n\n```\n",
		},
		{
			name: "leaves merge subjects alone",
			in:   "Merge pull request #17 from someone/branch\n",
			want: "Merge pull request #17 from someone/branch\n",
		},
		{
			name: "leaves revert subjects alone",
			in:   "Revert \"feat: add the thing.\"\n",
			want: "Revert \"feat: add the thing.\"\n",
		},
		{
			name: "leaves fixup subjects alone",
			in:   "fixup! feat: add the thing\n",
			want: "fixup! feat: add the thing\n",
		},
		{
			name: "handles CRLF line endings",
			in:   "fix: windows line endings.\r\n\r\nbody\r\n",
			want: "fix: windows line endings\n\nbody\n",
		},
		{
			name: "an all-comment message normalizes to empty",
			in:   "# nothing here\n",
			want: "",
		},
		{
			name: "does not rewrap a long body line",
			in:   "docs: a\n\n" + strings.Repeat("word ", 30) + "\n",
			want: "docs: a\n\n" + strings.TrimSpace(strings.Repeat("word ", 30)) + "\n",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Normalize(tt.in)
			if got != tt.want {
				t.Errorf("Normalize()\n got: %q\nwant: %q", got, tt.want)
			}
			if again := Normalize(got); again != got {
				t.Errorf("Normalize is not idempotent\nfirst: %q\nsecond: %q", got, again)
			}
		})
	}
}

func TestNormalizeIsIdempotentOnLintedOutput(t *testing.T) {
	msg := Normalize("Feat(cli):   Add the --timeout flag.  \n\n\nSome body text.\nNightshift-Task: commit-normalize\n")
	if issues := Lint(msg); len(issues) != 0 {
		t.Fatalf("normalized message should lint clean, got %v", issues)
	}
	if got := Normalize(msg); got != msg {
		t.Fatalf("not idempotent: %q vs %q", got, msg)
	}
}

func TestLintValid(t *testing.T) {
	valid := []string{
		"feat: add the budget rollover\n",
		"feat(cli): add the --timeout flag\n",
		"fix(config)!: rename the provider key\n",
		"docs: README.md gains a hook section\n",
		"feat: API key rotation\n",
		"chore: wire up the hook\n\nA body paragraph that stays well under the limit.\n\nNightshift-Task: commit-normalize\nNightshift-Ref: https://github.com/marcus/nightshift\n",
		"docs: link to the standard\n\nSee\nhttps://github.com/marcus/nightshift/blob/main/docs/commit-messages.md#the-trailer-block\nfor the full write-up.\n",
		"docs: show a snippet\n\n```\nthis fenced line is deliberately far longer than the seventy-two column limit\n```\n",
		"Merge pull request #17 from someone/branch\n",
		"Revert \"feat: add the thing\"\n",
	}
	for _, msg := range valid {
		t.Run(strings.SplitN(msg, "\n", 2)[0], func(t *testing.T) {
			if issues := Lint(msg); len(issues) != 0 {
				t.Errorf("expected no issues, got %v", issues)
			}
		})
	}
}

func TestLintInvalid(t *testing.T) {
	tests := []struct {
		name string
		in   string
		rule string
	}{
		{"empty", "\n#comment\n", "empty-message"},
		{"no type", "just do the thing\n", "missing-type"},
		{"unknown type", "feet: add the thing\n", "unknown-type"},
		{"missing space after colon", "feat:add the thing\n", "missing-space-after-colon"},
		{"empty scope", "feat(): add the thing\n", "empty-scope"},
		{"empty subject", "feat: \n", "empty-subject"},
		{"trailing period", "feat: add the thing.\n", "subject-trailing-period"},
		{"capitalized", "feat: Add the thing\n", "subject-capitalized"},
		{"too long", "feat: " + strings.Repeat("a", MaxSubjectLen) + "\n", "subject-too-long"},
		{"no blank line", "feat: add the thing\nbody starts immediately\n", "missing-blank-line"},
		{"body line too long", "feat: add the thing\n\n" + strings.Repeat("word ", 30) + "\n", "body-line-too-long"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			issues := Lint(tt.in)
			if len(issues) == 0 {
				t.Fatalf("expected issue %q, got none", tt.rule)
			}
			for _, issue := range issues {
				if issue.Rule == tt.rule {
					if issue.Msg == "" {
						t.Errorf("issue %q has an empty message", tt.rule)
					}
					return
				}
			}
			t.Errorf("expected issue %q, got %v", tt.rule, issues)
		})
	}
}

func TestTrailersAreNotLengthChecked(t *testing.T) {
	msg := "chore: record the task\n\nNightshift-Ref: https://github.com/marcus/nightshift/blob/main/docs/commit-messages.md#trailers\n"
	if issues := Lint(msg); len(issues) != 0 {
		t.Fatalf("trailer lines must be exempt from the width limit, got %v", issues)
	}
	if got := Normalize(msg); got != msg {
		t.Fatalf("trailers must survive normalization: %q", got)
	}
}

// The gap between the recommended wrap width and the enforced limit is
// deliberate; pin it so it is not narrowed by accident.
func TestBodyWidthSlack(t *testing.T) {
	body := func(n int) string {
		// n runes made of wrappable words.
		line := strings.TrimSpace(strings.Repeat("word ", n/5+2))
		return "feat: a thing\n\n" + string([]rune(line)[:n]) + "\n"
	}
	if issues := Lint(body(WrapBodyAt + 1)); len(issues) != 0 {
		t.Errorf("a line just over the wrap width should be tolerated, got %v", issues)
	}
	if issues := Lint(body(MaxBodyLineLen)); len(issues) != 0 {
		t.Errorf("a line at the hard limit should be accepted, got %v", issues)
	}
	if issues := Lint(body(MaxBodyLineLen + 1)); len(issues) == 0 {
		t.Error("a line over the hard limit should be rejected")
	}
}

func TestTypeListIsStable(t *testing.T) {
	got := strings.Join(TypeList(), ",")
	want := "build,chore,ci,docs,feat,fix,perf,refactor,revert,style,test"
	if got != want {
		t.Fatalf("TypeList() = %q, want %q", got, want)
	}
}
