// Command commitmsg normalizes and lints commit messages against the nightshift
// commit message standard documented in docs/commit-messages.md.
//
// Usage:
//
//	commitmsg normalize <file>          rewrite the message file in place
//	commitmsg lint <file>               validate one message file ("-" for stdin)
//	commitmsg lint --range <rev-range>  validate every commit in a range
//	commitmsg lint --range <r> --report-only
//	                                    report violations but always exit 0
//
// It exits 1 when a message violates the standard and 2 on usage or I/O errors.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/marcus/nightshift/internal/commitmsg"
)

const (
	exitViolation = 1
	exitUsage     = 2
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(exitUsage)
	}

	switch os.Args[1] {
	case "normalize":
		os.Exit(runNormalize(os.Args[2:]))
	case "lint":
		os.Exit(runLint(os.Args[2:]))
	case "-h", "--help", "help":
		usage()
		os.Exit(0)
	default:
		fmt.Fprintf(os.Stderr, "commitmsg: unknown command %q\n\n", os.Args[1])
		usage()
		os.Exit(exitUsage)
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `commitmsg — normalize and lint commit messages

Usage:
  commitmsg normalize <file>                 rewrite a message file in place
  commitmsg lint [file]                      validate a message file ("-" or
                                             omitted reads stdin)
  commitmsg lint --range <rev-range>         validate every commit in a range
  commitmsg lint --range <r> --report-only   report but always exit 0

The standard is documented in docs/commit-messages.md.
`)
}

func runNormalize(args []string) int {
	fs := flag.NewFlagSet("normalize", flag.ContinueOnError)
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if fs.NArg() != 1 {
		fmt.Fprintln(os.Stderr, "commitmsg normalize: expected exactly one message file")
		return exitUsage
	}

	path := fs.Arg(0)
	raw, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "commitmsg normalize: %v\n", err)
		return exitUsage
	}

	normalized := commitmsg.Normalize(string(raw))
	if normalized == string(raw) {
		return 0
	}
	info, err := os.Stat(path)
	mode := os.FileMode(0o644)
	if err == nil {
		mode = info.Mode().Perm()
	}
	if err := os.WriteFile(path, []byte(normalized), mode); err != nil {
		fmt.Fprintf(os.Stderr, "commitmsg normalize: %v\n", err)
		return exitUsage
	}
	return 0
}

func runLint(args []string) int {
	fs := flag.NewFlagSet("lint", flag.ContinueOnError)
	revRange := fs.String("range", "", "validate every commit in this git rev-range instead of a file")
	reportOnly := fs.Bool("report-only", false, "print violations but always exit 0")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}

	if *revRange != "" {
		if fs.NArg() > 0 {
			fmt.Fprintln(os.Stderr, "commitmsg lint: --range cannot be combined with a file argument")
			return exitUsage
		}
		return lintRange(*revRange, *reportOnly)
	}

	msg, err := readMessage(fs.Arg(0))
	if err != nil {
		fmt.Fprintf(os.Stderr, "commitmsg lint: %v\n", err)
		return exitUsage
	}
	issues := commitmsg.Lint(msg)
	if len(issues) == 0 {
		return 0
	}
	report(os.Stderr, firstLine(msg), issues)
	if *reportOnly {
		return 0
	}
	return exitViolation
}

func readMessage(path string) (string, error) {
	if path == "" || path == "-" {
		raw, err := io.ReadAll(os.Stdin)
		return string(raw), err
	}
	raw, err := os.ReadFile(path)
	return string(raw), err
}

func lintRange(revRange string, reportOnly bool) int {
	shas, err := gitLines("rev-list", "--no-merges", revRange)
	if err != nil {
		fmt.Fprintf(os.Stderr, "commitmsg lint: %v\n", err)
		return exitUsage
	}
	if len(shas) == 0 {
		fmt.Printf("commitmsg: no commits in range %s\n", revRange)
		return 0
	}

	bad := 0
	for _, sha := range shas {
		out, err := exec.Command("git", "log", "-1", "--pretty=%B", sha).Output()
		if err != nil {
			fmt.Fprintf(os.Stderr, "commitmsg lint: reading %s: %v\n", sha, err)
			return exitUsage
		}
		msg := string(out)
		issues := commitmsg.Lint(msg)
		if len(issues) == 0 {
			continue
		}
		bad++
		report(os.Stderr, fmt.Sprintf("%s %s", shortSHA(sha), firstLine(msg)), issues)
	}

	fmt.Printf("commitmsg: checked %d commit(s) in %s, %d with violations\n", len(shas), revRange, bad)
	if bad > 0 && !reportOnly {
		fmt.Fprintln(os.Stderr, "\nSee docs/commit-messages.md for the standard.")
		return exitViolation
	}
	return 0
}

func report(w io.Writer, header string, issues []commitmsg.Issue) {
	fmt.Fprintf(w, "✗ %s\n", header)
	for _, issue := range issues {
		fmt.Fprintf(w, "    %s\n", issue)
	}
}

func gitLines(args ...string) ([]string, error) {
	out, err := exec.Command("git", args...).Output()
	if err != nil {
		return nil, fmt.Errorf("git %s: %w", strings.Join(args, " "), err)
	}
	var lines []string
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line != "" {
			lines = append(lines, line)
		}
	}
	return lines, nil
}

func firstLine(msg string) string {
	for _, line := range strings.Split(msg, "\n") {
		line = strings.TrimSpace(line)
		if line != "" && !strings.HasPrefix(line, "#") {
			return line
		}
	}
	return "(empty message)"
}

func shortSHA(sha string) string {
	if len(sha) > 8 {
		return sha[:8]
	}
	return sha
}
