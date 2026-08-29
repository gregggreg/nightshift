package commands

import (
	"fmt"
	"io"
	"os"

	"github.com/spf13/cobra"

	"github.com/marcus/nightshift/internal/commitmsg"
)

// commitMsgOptions holds the parsed flags for `nightshift commit-msg`.
type commitMsgOptions struct {
	check     bool
	fix       bool
	printSpec bool
	quiet     bool
}

func newCommitMsgCmd() *cobra.Command {
	opts := &commitMsgOptions{}

	cmd := &cobra.Command{
		Use:   "commit-msg [file|-]",
		Short: "Check or normalize a commit message",
		Long: `Check a commit message against the repository's commit format, or
rewrite it into that format.

Reads the message from FILE, or from stdin when FILE is "-" or omitted.
This is what the commit-msg git hook runs; install it with:

    make install-hooks

Examples:
  nightshift commit-msg --print-spec
  nightshift commit-msg --check .git/COMMIT_EDITMSG
  nightshift commit-msg --fix .git/COMMIT_EDITMSG
  printf 'Fixed the thing.' | nightshift commit-msg --fix -`,
		Args:         cobra.MaximumNArgs(1),
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			path := "-"
			if len(args) == 1 {
				path = args[0]
			}
			return runCommitMsg(path, opts, cmd.InOrStdin(), cmd.OutOrStdout(), cmd.ErrOrStderr())
		},
	}

	cmd.Flags().BoolVar(&opts.check, "check", false, "Validate only; exit non-zero when the message has errors")
	cmd.Flags().BoolVar(&opts.fix, "fix", false, "Rewrite the message into the canonical format")
	cmd.Flags().BoolVar(&opts.printSpec, "print-spec", false, "Print the commit message format and exit")
	cmd.Flags().BoolVar(&opts.quiet, "quiet", false, "Suppress issue output; rely on the exit code")

	return cmd
}

func init() {
	rootCmd.AddCommand(newCommitMsgCmd())
}

func runCommitMsg(path string, opts *commitMsgOptions, stdin io.Reader, stdout, stderr io.Writer) error {
	if opts.printSpec {
		fmt.Fprint(stdout, commitmsg.Spec())
		return nil
	}
	if opts.check && opts.fix {
		return fmt.Errorf("--check and --fix are mutually exclusive")
	}

	raw, err := readCommitMsg(path, stdin)
	if err != nil {
		return err
	}

	label := path
	if label == "-" {
		label = "<stdin>"
	}

	if opts.fix {
		fixed, issues, err := commitmsg.Normalize(raw, commitMsgValidationOptions())
		if err != nil {
			return fmt.Errorf("%s: %w\n\n%s", label, err, commitmsg.Spec())
		}
		if path == "-" {
			fmt.Fprint(stdout, fixed)
		} else if fixed != raw {
			if err := os.WriteFile(path, []byte(fixed), 0o644); err != nil {
				return fmt.Errorf("writing %s: %w", path, err)
			}
		}
		reportCommitMsgIssues(stderr, label, issues, opts.quiet)
		if commitmsg.HasErrors(issues) {
			return fmt.Errorf("%s: commit message still has errors after --fix", label)
		}
		return nil
	}

	// Default behaviour, with or without an explicit --check, is to validate.
	msg, err := commitmsg.Parse(raw)
	if err != nil {
		return fmt.Errorf("%s: %w", label, err)
	}
	issues := commitmsg.ValidateWithOptions(msg, commitMsgValidationOptions())
	reportCommitMsgIssues(stderr, label, issues, opts.quiet)
	if commitmsg.HasErrors(issues) {
		if !opts.quiet {
			fmt.Fprintf(stderr, "\n%s", commitmsg.Spec())
		}
		return fmt.Errorf("%s: commit message does not match the required format", label)
	}
	return nil
}

// commitMsgValidationOptions returns the validation options the CLI enforces. Nightshift
// trailers are not required of humans, so the defaults are used as-is.
func commitMsgValidationOptions() commitmsg.Options {
	return commitmsg.DefaultOptions()
}

func readCommitMsg(path string, stdin io.Reader) (string, error) {
	if path == "-" {
		data, err := io.ReadAll(stdin)
		if err != nil {
			return "", fmt.Errorf("reading stdin: %w", err)
		}
		return string(data), nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("reading %s: %w", path, err)
	}
	return string(data), nil
}

// reportCommitMsgIssues prints issues as "file:line: severity: message (rule)".
func reportCommitMsgIssues(w io.Writer, label string, issues []commitmsg.Issue, quiet bool) {
	if quiet {
		return
	}
	for _, i := range issues {
		line := "-"
		if i.Line > 0 {
			line = fmt.Sprintf("%d", i.Line)
		}
		fmt.Fprintf(w, "%s:%s: %s: %s (%s)\n", label, line, i.Severity, i.Message, i.Rule)
	}
}
