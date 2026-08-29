package commitmsg

import (
	"strings"
	"testing"
)

func hasRule(issues []Issue, rule string) bool {
	for _, i := range issues {
		if i.Rule == rule {
			return true
		}
	}
	return false
}

func errorCount(issues []Issue) int {
	n := 0
	for _, i := range issues {
		if i.Severity == SeverityError {
			n++
		}
	}
	return n
}

// --- Parsing ---

func TestParse_FullMessage(t *testing.T) {
	raw := `feat(cli): add commit message normalizer

This adds a normalizer that enforces a single commit format
across the repository.

Nightshift-Task: commit-normalize
Co-Authored-By: Someone <someone@example.com>
`
	m, err := Parse(raw)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if m.Type != "feat" {
		t.Errorf("Type = %q, want feat", m.Type)
	}
	if m.Scope != "cli" {
		t.Errorf("Scope = %q, want cli", m.Scope)
	}
	if m.Breaking {
		t.Errorf("Breaking = true, want false")
	}
	if m.Subject != "add commit message normalizer" {
		t.Errorf("Subject = %q", m.Subject)
	}
	if !strings.HasPrefix(m.Body, "This adds a normalizer") {
		t.Errorf("Body = %q", m.Body)
	}
	if strings.Contains(m.Body, "Nightshift-Task") {
		t.Errorf("body should not contain trailers: %q", m.Body)
	}
	if len(m.Trailers) != 2 {
		t.Fatalf("Trailers = %v, want 2", m.Trailers)
	}
	if m.Trailers[0].Key != "Nightshift-Task" || m.Trailers[0].Value != "commit-normalize" {
		t.Errorf("Trailers[0] = %+v", m.Trailers[0])
	}
	if m.Trailers[1].Key != "Co-Authored-By" {
		t.Errorf("Trailers[1] = %+v", m.Trailers[1])
	}
}

func TestParse_BreakingMarker(t *testing.T) {
	m, err := Parse("feat(api)!: drop v1 endpoints")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if !m.Breaking {
		t.Errorf("Breaking = false, want true")
	}
	if m.Type != "feat" || m.Scope != "api" {
		t.Errorf("got type=%q scope=%q", m.Type, m.Scope)
	}
	if m.Subject != "drop v1 endpoints" {
		t.Errorf("Subject = %q", m.Subject)
	}
}

func TestParse_NoConventionalHeader(t *testing.T) {
	m, err := Parse("Fixed the flaky test")
	if err != nil {
		t.Fatalf("Parse should not fail on a non-conventional header: %v", err)
	}
	if m.Type != "" {
		t.Errorf("Type = %q, want empty", m.Type)
	}
	if m.Subject != "Fixed the flaky test" {
		t.Errorf("Subject = %q", m.Subject)
	}
}

func TestParse_EmptyMessage(t *testing.T) {
	for _, raw := range []string{"", "   \n\n  ", "# just a comment\n# another\n"} {
		if _, err := Parse(raw); err == nil {
			t.Errorf("Parse(%q) = nil error, want error", raw)
		}
	}
}

func TestParse_StripsCommentsAndVerboseDiff(t *testing.T) {
	raw := `fix(db): close rows on scan error

# Please enter the commit message for your changes. Lines starting
# with '#' will be ignored, and an empty message aborts the commit.
#
# ------------------------ >8 ------------------------
# Do not modify or remove the line above.
diff --git a/internal/db/db.go b/internal/db/db.go
index 1234567..89abcde 100644
--- a/internal/db/db.go
+++ b/internal/db/db.go
@@ -1,3 +1,4 @@
+// a change that must never leak into the message
`
	m, err := Parse(raw)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if m.Body != "" {
		t.Errorf("Body = %q, want empty (comments and diff stripped)", m.Body)
	}
	if strings.Contains(m.String(), "diff --git") || strings.Contains(m.String(), "#") {
		t.Errorf("String() leaked comments/diff:\n%s", m.String())
	}
}

func TestMessage_String_RoundTrip(t *testing.T) {
	raw := "feat(cli): add thing\n\nSome body text.\n\nNightshift-Task: commit-normalize\n"
	m, err := Parse(raw)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	want := "feat(cli): add thing\n\nSome body text.\n\nNightshift-Task: commit-normalize"
	if got := m.String(); got != want {
		t.Errorf("String() =\n%q\nwant\n%q", got, want)
	}
}

// --- Validation ---

func TestValidate_Clean(t *testing.T) {
	m, err := Parse("feat(cli): add commit message normalizer\n\nA short body.\n")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if issues := Validate(m); len(issues) != 0 {
		t.Errorf("Validate() = %v, want none", issues)
	}
}

func TestValidate_MissingType(t *testing.T) {
	m, _ := Parse("Fixed the flaky test")
	issues := Validate(m)
	if !hasRule(issues, "header-format") {
		t.Errorf("expected header-format issue, got %v", issues)
	}
	if errorCount(issues) == 0 {
		t.Errorf("expected at least one error-severity issue, got %v", issues)
	}
}

func TestValidate_UnknownType(t *testing.T) {
	m, _ := Parse("feet(cli): add a thing")
	if !hasRule(Validate(m), "type-allowed") {
		t.Errorf("expected type-allowed issue, got %v", Validate(m))
	}
}

func TestValidate_UppercaseType(t *testing.T) {
	m, _ := Parse("Fix(cli): add a thing")
	if !hasRule(Validate(m), "type-lowercase") {
		t.Errorf("expected type-lowercase issue, got %v", Validate(m))
	}
}

func TestValidate_EmptySubject(t *testing.T) {
	m, _ := Parse("fix(cli):")
	if !hasRule(Validate(m), "subject-empty") && !hasRule(Validate(m), "header-format") {
		t.Errorf("expected an issue for an empty subject, got %v", Validate(m))
	}
}

func TestValidate_SubjectTooLong(t *testing.T) {
	long := "feat(cli): " + strings.Repeat("a", 80)
	m, _ := Parse(long)
	issues := Validate(m)
	if !hasRule(issues, "subject-length") {
		t.Errorf("expected subject-length issue, got %v", issues)
	}
	for _, i := range issues {
		if i.Rule == "subject-length" && i.Severity != SeverityError {
			t.Errorf("subject-length should be an error, got %v", i.Severity)
		}
	}
}

func TestValidate_TrailingPeriod(t *testing.T) {
	m, _ := Parse("fix(cli): stop panicking on empty input.")
	if !hasRule(Validate(m), "subject-trailing-period") {
		t.Errorf("expected subject-trailing-period issue, got %v", Validate(m))
	}
}

func TestValidate_ImperativeMoodWarning(t *testing.T) {
	m, _ := Parse("fix(cli): fixed the parser")
	issues := Validate(m)
	if !hasRule(issues, "subject-mood") {
		t.Fatalf("expected subject-mood issue, got %v", issues)
	}
	for _, i := range issues {
		if i.Rule == "subject-mood" && i.Severity != SeverityWarning {
			t.Errorf("subject-mood should be a warning, got %v", i.Severity)
		}
	}
}

func TestValidate_MissingBlankLineAfterSubject(t *testing.T) {
	m, _ := Parse("fix(cli): stop panicking\nthe body starts immediately\n")
	if !hasRule(Validate(m), "body-blank-line") {
		t.Errorf("expected body-blank-line issue, got %v", Validate(m))
	}
}

func TestValidate_BodyWrapWarning(t *testing.T) {
	m, _ := Parse("fix(cli): wrap it\n\n" + strings.Repeat("word ", 30) + "\n")
	issues := Validate(m)
	if !hasRule(issues, "body-wrap") {
		t.Fatalf("expected body-wrap issue, got %v", issues)
	}
	for _, i := range issues {
		if i.Rule == "body-wrap" && i.Severity != SeverityWarning {
			t.Errorf("body-wrap should be a warning, got %v", i.Severity)
		}
	}
}

func TestValidateWithOptions_RequiredTrailers(t *testing.T) {
	opts := DefaultOptions()
	opts.RequiredTrailers = []Trailer{{Key: "Nightshift-Task", Value: "commit-normalize"}}

	m, _ := Parse("fix(cli): stop panicking")
	if !hasRule(ValidateWithOptions(m, opts), "trailer-required") {
		t.Errorf("expected trailer-required issue, got %v", ValidateWithOptions(m, opts))
	}

	m2, _ := Parse("fix(cli): stop panicking\n\nNightshift-Task: commit-normalize\n")
	if hasRule(ValidateWithOptions(m2, opts), "trailer-required") {
		t.Errorf("unexpected trailer-required issue: %v", ValidateWithOptions(m2, opts))
	}
}

func TestIssue_String(t *testing.T) {
	i := Issue{Line: 3, Severity: SeverityError, Rule: "subject-length", Message: "too long"}
	got := i.String()
	if !strings.Contains(got, "3") || !strings.Contains(got, "error") || !strings.Contains(got, "too long") {
		t.Errorf("Issue.String() = %q", got)
	}
}

// --- Normalization ---

func TestNormalize_InfersTypeFromSubject(t *testing.T) {
	cases := []struct {
		raw  string
		want string
	}{
		{"Fixed bug in X.", "fix: fixed bug in X"},
		{"Added a new report command", "feat: added a new report command"},
		{"Update the README", "docs: update the README"},
		{"Refactored the orchestrator", "refactor: refactored the orchestrator"},
		{"Bump go version", "chore: bump go version"},
	}
	for _, tc := range cases {
		got, _, err := Normalize(tc.raw, DefaultOptions())
		if err != nil {
			t.Errorf("Normalize(%q): %v", tc.raw, err)
			continue
		}
		if strings.TrimRight(got, "\n") != tc.want {
			t.Errorf("Normalize(%q) = %q, want %q", tc.raw, strings.TrimRight(got, "\n"), tc.want)
		}
	}
}

func TestNormalize_UninferrableTypeIsAnError(t *testing.T) {
	if _, issues, err := Normalize("zzzqqq wibble frobnicate", DefaultOptions()); err == nil {
		t.Errorf("expected error for uninferrable type, got issues %v", issues)
	}
}

func TestNormalize_LowercasesTypeAndStripsPeriod(t *testing.T) {
	got, _, err := Normalize("Fix(CLI): stop panicking on empty input.", DefaultOptions())
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	want := "fix(CLI): stop panicking on empty input\n"
	if got != want {
		t.Errorf("Normalize() = %q, want %q", got, want)
	}
}

func TestNormalize_PreservesAcronymInSubject(t *testing.T) {
	got, _, err := Normalize("Fixed API timeouts", DefaultOptions())
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	if !strings.Contains(got, "API timeouts") {
		t.Errorf("Normalize() = %q, want the acronym preserved", got)
	}
}

func TestNormalize_InsertsBlankLineBeforeBody(t *testing.T) {
	got, _, err := Normalize("fix(cli): stop panicking\nthe body starts immediately\n", DefaultOptions())
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	want := "fix(cli): stop panicking\n\nthe body starts immediately\n"
	if got != want {
		t.Errorf("Normalize() = %q, want %q", got, want)
	}
}

func TestNormalize_WrapsBody(t *testing.T) {
	body := strings.Repeat("word ", 40)
	got, _, err := Normalize("fix(cli): wrap it\n\n"+body+"\n", DefaultOptions())
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	for _, line := range strings.Split(got, "\n") {
		if len(line) > DefaultOptions().WrapBody {
			t.Errorf("line exceeds wrap width (%d): %q", len(line), line)
		}
	}
}

func TestNormalize_DoesNotWrapCodeOrURLs(t *testing.T) {
	url := "https://example.com/" + strings.Repeat("a", 90)
	raw := "docs: add link\n\n    indented code line that is quite long and should not be rewrapped at all\n\n" + url + "\n"
	got, _, err := Normalize(raw, DefaultOptions())
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	if !strings.Contains(got, url) {
		t.Errorf("URL was rewrapped:\n%s", got)
	}
	if !strings.Contains(got, "    indented code line that is quite long and should not be rewrapped at all") {
		t.Errorf("indented line was rewrapped:\n%s", got)
	}
}

func TestNormalize_AppendsRequiredTrailers(t *testing.T) {
	opts := DefaultOptions()
	opts.RequiredTrailers = []Trailer{
		{Key: "Nightshift-Task", Value: "commit-normalize"},
		{Key: "Nightshift-Ref", Value: "https://github.com/marcus/nightshift"},
	}
	got, _, err := Normalize("fix(cli): stop panicking\n\nA body.\n", opts)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	want := "fix(cli): stop panicking\n\nA body.\n\nNightshift-Task: commit-normalize\nNightshift-Ref: https://github.com/marcus/nightshift\n"
	if got != want {
		t.Errorf("Normalize() =\n%q\nwant\n%q", got, want)
	}
}

func TestNormalize_DedupesTrailersAndPreservesCoAuthors(t *testing.T) {
	opts := DefaultOptions()
	opts.RequiredTrailers = []Trailer{{Key: "Nightshift-Task", Value: "commit-normalize"}}
	raw := `fix(cli): stop panicking

Nightshift-Task: commit-normalize
Nightshift-Task: commit-normalize
Co-Authored-By: A <a@example.com>
Co-Authored-By: B <b@example.com>
Co-Authored-By: A <a@example.com>
`
	got, _, err := Normalize(raw, opts)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	if n := strings.Count(got, "Nightshift-Task:"); n != 1 {
		t.Errorf("Nightshift-Task appears %d times:\n%s", n, got)
	}
	if n := strings.Count(got, "Co-Authored-By: A <a@example.com>"); n != 1 {
		t.Errorf("duplicate co-author not deduped:\n%s", got)
	}
	if !strings.Contains(got, "Co-Authored-By: B <b@example.com>") {
		t.Errorf("distinct co-author dropped:\n%s", got)
	}
}

func TestNormalize_TrailersEndUpInASingleTrailingBlock(t *testing.T) {
	raw := `fix(cli): stop panicking

Nightshift-Task: commit-normalize

Some body text that came after a trailer.

Co-Authored-By: A <a@example.com>
`
	got, _, err := Normalize(raw, DefaultOptions())
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	lines := strings.Split(strings.TrimRight(got, "\n"), "\n")
	// The last block must be contiguous trailers.
	if lines[len(lines)-1] != "Co-Authored-By: A <a@example.com>" ||
		lines[len(lines)-2] != "Nightshift-Task: commit-normalize" {
		t.Errorf("trailers not collected into one trailing block:\n%s", got)
	}
	if lines[len(lines)-3] != "" {
		t.Errorf("missing blank line before trailer block:\n%s", got)
	}
}

func TestNormalize_Idempotent(t *testing.T) {
	opts := DefaultOptions()
	opts.RequiredTrailers = []Trailer{{Key: "Nightshift-Task", Value: "commit-normalize"}}
	inputs := []string{
		"Fixed bug in X.",
		"fix(cli): stop panicking\nbody right here\n",
		"feat(api)!: drop v1\n\n" + strings.Repeat("word ", 40) + "\n\nCo-Authored-By: A <a@example.com>\n",
	}
	for _, raw := range inputs {
		once, _, err := Normalize(raw, opts)
		if err != nil {
			t.Fatalf("Normalize(%q): %v", raw, err)
		}
		twice, _, err := Normalize(once, opts)
		if err != nil {
			t.Fatalf("Normalize(normalized): %v", err)
		}
		if once != twice {
			t.Errorf("not idempotent for %q:\nfirst:\n%q\nsecond:\n%q", raw, once, twice)
		}
	}
}

func TestNormalize_AlreadyNormalIsNoOp(t *testing.T) {
	raw := "feat(cli): add commit message normalizer\n\nA tidy body that is already short enough.\n\nNightshift-Task: commit-normalize\n"
	got, issues, err := Normalize(raw, DefaultOptions())
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	if got != raw {
		t.Errorf("Normalize() changed an already-normal message:\ngot  %q\nwant %q", got, raw)
	}
	if errorCount(issues) != 0 {
		t.Errorf("unexpected residual errors: %v", issues)
	}
}

func TestNormalize_ReportsResidualErrorsItCannotFix(t *testing.T) {
	long := "feat(cli): " + strings.Repeat("a", 90)
	_, issues, err := Normalize(long, DefaultOptions())
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	if !hasRule(issues, "subject-length") {
		t.Errorf("expected residual subject-length issue, got %v", issues)
	}
}

func TestNormalize_StripsCommentsAndDiff(t *testing.T) {
	raw := "fix(db): close rows\n# a comment\n# ------------------------ >8 ------------------------\ndiff --git a/x b/x\n+leak\n"
	got, _, err := Normalize(raw, DefaultOptions())
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	if got != "fix(db): close rows\n" {
		t.Errorf("Normalize() = %q", got)
	}
}

// --- Spec ---

func TestSpec_MentionsCoreRules(t *testing.T) {
	s := Spec()
	for _, want := range []string{"type(scope)", "72", "feat", "fix"} {
		if !strings.Contains(s, want) {
			t.Errorf("Spec() missing %q:\n%s", want, s)
		}
	}
}

func TestPromptSpec_IncludesTrailers(t *testing.T) {
	s := PromptSpec("commit-normalize")
	if !strings.Contains(s, "Nightshift-Task: commit-normalize") {
		t.Errorf("PromptSpec missing task trailer:\n%s", s)
	}
	if !strings.Contains(s, "Nightshift-Ref: https://github.com/marcus/nightshift") {
		t.Errorf("PromptSpec missing ref trailer:\n%s", s)
	}
}
