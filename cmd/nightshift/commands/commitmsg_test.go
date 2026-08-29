package commands

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTempMsg(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "COMMIT_EDITMSG")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("writing temp message: %v", err)
	}
	return path
}

func TestRunCommitMsg_PrintSpec(t *testing.T) {
	var out, errBuf bytes.Buffer
	if err := runCommitMsg("-", &commitMsgOptions{printSpec: true}, strings.NewReader(""), &out, &errBuf); err != nil {
		t.Fatalf("runCommitMsg: %v", err)
	}
	if !strings.Contains(out.String(), "type(scope)") {
		t.Errorf("--print-spec output missing the format:\n%s", out.String())
	}
}

func TestRunCommitMsg_CheckPassesOnGoodFile(t *testing.T) {
	path := writeTempMsg(t, "feat(cli): add commit message normalizer\n\nA short body.\n")
	var out, errBuf bytes.Buffer
	if err := runCommitMsg(path, &commitMsgOptions{check: true}, strings.NewReader(""), &out, &errBuf); err != nil {
		t.Fatalf("runCommitMsg: %v\nstderr: %s", err, errBuf.String())
	}
	if errBuf.Len() != 0 {
		t.Errorf("unexpected diagnostics: %s", errBuf.String())
	}
}

func TestRunCommitMsg_CheckFailsOnBadFile(t *testing.T) {
	path := writeTempMsg(t, "Fixed the thing.\n")
	var out, errBuf bytes.Buffer
	err := runCommitMsg(path, &commitMsgOptions{check: true}, strings.NewReader(""), &out, &errBuf)
	if err == nil {
		t.Fatalf("expected an error for a malformed message")
	}
	if !strings.Contains(errBuf.String(), "header-format") {
		t.Errorf("expected header-format diagnostic, got:\n%s", errBuf.String())
	}
	if !strings.Contains(errBuf.String(), path+":1:") {
		t.Errorf("expected file:line prefixed diagnostics, got:\n%s", errBuf.String())
	}
	if !strings.Contains(errBuf.String(), "type(scope)") {
		t.Errorf("expected the spec to be printed on failure, got:\n%s", errBuf.String())
	}
}

func TestRunCommitMsg_CheckQuietSuppressesOutput(t *testing.T) {
	path := writeTempMsg(t, "Fixed the thing.\n")
	var out, errBuf bytes.Buffer
	if err := runCommitMsg(path, &commitMsgOptions{check: true, quiet: true}, strings.NewReader(""), &out, &errBuf); err == nil {
		t.Fatalf("expected an error for a malformed message")
	}
	if errBuf.Len() != 0 {
		t.Errorf("--quiet should suppress diagnostics, got:\n%s", errBuf.String())
	}
}

func TestRunCommitMsg_FixRewritesFileInPlace(t *testing.T) {
	path := writeTempMsg(t, "Fixed bug in the parser.\n# a comment git added\n")
	var out, errBuf bytes.Buffer
	if err := runCommitMsg(path, &commitMsgOptions{fix: true}, strings.NewReader(""), &out, &errBuf); err != nil {
		t.Fatalf("runCommitMsg: %v\nstderr: %s", err, errBuf.String())
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading fixed file: %v", err)
	}
	if string(got) != "fix: fixed bug in the parser\n" {
		t.Errorf("fixed file = %q", string(got))
	}
	// The rewritten message must now pass --check.
	if err := runCommitMsg(path, &commitMsgOptions{check: true, quiet: true}, strings.NewReader(""), &out, &errBuf); err != nil {
		t.Errorf("fixed message still fails --check: %v", err)
	}
}

func TestRunCommitMsg_FixFromStdinWritesToStdout(t *testing.T) {
	var out, errBuf bytes.Buffer
	err := runCommitMsg("-", &commitMsgOptions{fix: true}, strings.NewReader("Fixed bug in the parser."), &out, &errBuf)
	if err != nil {
		t.Fatalf("runCommitMsg: %v\nstderr: %s", err, errBuf.String())
	}
	if out.String() != "fix: fixed bug in the parser\n" {
		t.Errorf("stdout = %q", out.String())
	}
}

func TestRunCommitMsg_CheckFromStdin(t *testing.T) {
	var out, errBuf bytes.Buffer
	err := runCommitMsg("-", &commitMsgOptions{check: true}, strings.NewReader("Fixed the thing."), &out, &errBuf)
	if err == nil {
		t.Fatalf("expected an error for a malformed message")
	}
	if !strings.Contains(errBuf.String(), "<stdin>:1:") {
		t.Errorf("expected <stdin> label, got:\n%s", errBuf.String())
	}
}

func TestRunCommitMsg_FixReportsUninferrableType(t *testing.T) {
	var out, errBuf bytes.Buffer
	err := runCommitMsg("-", &commitMsgOptions{fix: true}, strings.NewReader("zzzqqq wibble frobnicate"), &out, &errBuf)
	if err == nil {
		t.Fatalf("expected an error when no type can be inferred")
	}
	if !strings.Contains(err.Error(), "cannot infer") {
		t.Errorf("error = %v, want it to explain the inference failure", err)
	}
}

func TestRunCommitMsg_CheckAndFixAreExclusive(t *testing.T) {
	var out, errBuf bytes.Buffer
	err := runCommitMsg("-", &commitMsgOptions{check: true, fix: true}, strings.NewReader("fix: a thing"), &out, &errBuf)
	if err == nil || !strings.Contains(err.Error(), "mutually exclusive") {
		t.Errorf("err = %v, want a mutual-exclusion error", err)
	}
}

func TestRunCommitMsg_MissingFile(t *testing.T) {
	var out, errBuf bytes.Buffer
	err := runCommitMsg(filepath.Join(t.TempDir(), "nope"), &commitMsgOptions{check: true}, strings.NewReader(""), &out, &errBuf)
	if err == nil {
		t.Fatalf("expected an error for a missing file")
	}
}

func TestCommitMsgCmd_EndToEnd(t *testing.T) {
	path := writeTempMsg(t, "Fixed bug in the parser.\n")

	cmd := newCommitMsgCmd()
	var out, errBuf bytes.Buffer
	cmd.SetOut(&out)
	cmd.SetErr(&errBuf)
	cmd.SetArgs([]string{"--fix", path})
	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute: %v\nstderr: %s", err, errBuf.String())
	}

	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading fixed file: %v", err)
	}
	if string(got) != "fix: fixed bug in the parser\n" {
		t.Errorf("fixed file = %q", string(got))
	}
}

func TestRunCommitMsg_AcceptsGitGeneratedMessages(t *testing.T) {
	for _, raw := range []string{
		"Merge branch 'side'\n",
		"Merge branch 'side'\n\n# Conflicts:\n#\tfile.go\n",
		"Revert \"feat(cli): add commit message normalizer\"\n\nThis reverts commit deadbeef.\n",
		"fixup! feat(cli): add commit message normalizer\n",
		"squash! feat(cli): add commit message normalizer\n",
		"amend! feat(cli): add commit message normalizer\n",
	} {
		path := writeTempMsg(t, raw)
		var out, errBuf bytes.Buffer
		if err := runCommitMsg(path, &commitMsgOptions{check: true}, strings.NewReader(""), &out, &errBuf); err != nil {
			t.Errorf("check %q: %v\nstderr: %s", raw, err, errBuf.String())
		}
	}
}

func TestRunCommitMsg_FixLeavesGitGeneratedAlone(t *testing.T) {
	raw := "Merge branch 'side' into main\n"
	path := writeTempMsg(t, raw)
	var out, errBuf bytes.Buffer
	if err := runCommitMsg(path, &commitMsgOptions{fix: true}, strings.NewReader(""), &out, &errBuf); err != nil {
		t.Fatalf("fix: %v\nstderr: %s", err, errBuf.String())
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading file: %v", err)
	}
	if string(got) != raw {
		t.Errorf("fixed file = %q, want it unchanged", string(got))
	}
}

func TestRunCommitMsg_PrintSpecMentionsGitGeneratedExemption(t *testing.T) {
	var out, errBuf bytes.Buffer
	if err := runCommitMsg("-", &commitMsgOptions{printSpec: true}, strings.NewReader(""), &out, &errBuf); err != nil {
		t.Fatalf("print-spec: %v", err)
	}
	if !strings.Contains(out.String(), "fixup! ") || !strings.Contains(out.String(), "Merge ") {
		t.Errorf("spec does not document the git-generated exemption:\n%s", out.String())
	}
}
