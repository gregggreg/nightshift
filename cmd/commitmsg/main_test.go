package main

import (
	"os"
	"path/filepath"
	"testing"
)

func writeMsg(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "COMMIT_EDITMSG")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("writing message file: %v", err)
	}
	return path
}

func readMsgFile(t *testing.T, path string) string {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading message file: %v", err)
	}
	return string(raw)
}

func TestRunNormalizeRewritesFileInPlace(t *testing.T) {
	path := writeMsg(t, "Feat(cli):  Add the --timeout flag.  \nBody line.\n# a comment\n")

	if code := runNormalize([]string{path}); code != 0 {
		t.Fatalf("runNormalize exited %d, want 0", code)
	}

	want := "feat(cli): add the --timeout flag\n\nBody line.\n"
	if got := readMsgFile(t, path); got != want {
		t.Fatalf("normalized file =\n%q\nwant\n%q", got, want)
	}

	// Running again must not change the file.
	if code := runNormalize([]string{path}); code != 0 {
		t.Fatalf("second runNormalize exited %d, want 0", code)
	}
	if got := readMsgFile(t, path); got != want {
		t.Fatalf("normalize is not idempotent through the CLI: %q", got)
	}
}

func TestRunNormalizeMissingArgs(t *testing.T) {
	if code := runNormalize(nil); code != exitUsage {
		t.Fatalf("runNormalize with no file exited %d, want %d", code, exitUsage)
	}
	if code := runNormalize([]string{filepath.Join(t.TempDir(), "nope")}); code != exitUsage {
		t.Fatalf("runNormalize with a missing file exited %d, want %d", code, exitUsage)
	}
}

func TestRunLintExitCodes(t *testing.T) {
	tests := []struct {
		name string
		msg  string
		want int
	}{
		{"valid", "feat(cli): add the --timeout flag\n", 0},
		{"invalid", "Fixed the thing.\n", exitViolation},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if code := runLint([]string{writeMsg(t, tt.msg)}); code != tt.want {
				t.Fatalf("runLint exited %d, want %d", code, tt.want)
			}
		})
	}
}

func TestRunLintReportOnlyAlwaysSucceeds(t *testing.T) {
	path := writeMsg(t, "Fixed the thing.\n")
	if code := runLint([]string{"--report-only", path}); code != 0 {
		t.Fatalf("runLint --report-only exited %d, want 0", code)
	}
}

func TestRunLintRejectsRangeWithFile(t *testing.T) {
	if code := runLint([]string{"--range", "HEAD~1..HEAD", "some-file"}); code != exitUsage {
		t.Fatalf("runLint exited %d, want %d", code, exitUsage)
	}
}

func TestFirstLineSkipsCommentsAndBlanks(t *testing.T) {
	if got := firstLine("\n# comment\nfeat: a thing\n"); got != "feat: a thing" {
		t.Fatalf("firstLine() = %q", got)
	}
	if got := firstLine("# only comments\n"); got != "(empty message)" {
		t.Fatalf("firstLine() = %q", got)
	}
}
