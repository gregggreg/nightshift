# Commit message convention

nightshift uses [Conventional Commits](https://www.conventionalcommits.org/). Roughly
three quarters of the existing history already follows this shape — this guide makes it
explicit and enforceable for new work.

**History is not rewritten.** Enforcement applies to new commits only: the `commit-msg`
hook checks what you write locally, and the `commit-lint` CI job checks the commits in a
pull request. Commits already on `main` are left alone.

## Format

```
<type>(<optional scope>): <subject>

<optional body, wrapped at 72 columns>

<optional footers>
```

### Subject

| Rule | Detail |
| --- | --- |
| Type | One of the types below, lowercase |
| Scope | Optional, lowercase, in parentheses — a package or area (`orchestrator`, `internal/tasks`, `#19`) |
| Breaking | Append `!` before the colon (`feat(config)!: ...`) |
| Separator | A colon and a single space |
| Mood | Imperative — "add", not "adds", "added", or "Add" |
| Case | Starts lowercase; acronyms such as `JSONL` or `PR` are fine |
| Length | 72 characters or fewer, including the type and scope (characters, not bytes — accents and emoji count as one) |
| Punctuation | No trailing period |

### Types

| Type | Use for |
| --- | --- |
| `feat` | A new user-facing capability |
| `fix` | A bug fix |
| `docs` | Documentation only |
| `refactor` | A change that neither fixes a bug nor adds a feature |
| `test` | Adding or correcting tests |
| `chore` | Maintenance that does not fit elsewhere (version bumps, housekeeping) |
| `build` | Build system, `go.mod`, release packaging |
| `ci` | CI configuration and workflows |
| `perf` | A performance improvement |
| `style` | Formatting only, no behavior change (`gofmt`) |
| `revert` | Reverting a previous commit |

### Body

Optional. Separate it from the subject with a blank line and wrap at 72 columns.
Explain *what* changed and *why*; the diff already shows *how*.

The hook wraps at 72 by convention but only rejects body lines longer than 100
characters, so prose you deliberately keep on one line is not blocked. Trailers
and unbreakable single tokens such as URLs are exempt from the limit entirely.

### Footers

```
fixes #21
BREAKING CHANGE: budget.daily is now budget.per_day
```

Agent-authored commits produced by a nightshift run must keep their trailers, which the
validator accepts as footers:

```
Nightshift-Task: commit-normalize
Nightshift-Ref: https://github.com/marcus/nightshift
```

## Examples

Good — all drawn from the existing history:

```
feat(orchestrator): implement plan-implement-review loop (td-d50819)
fix: use week-aware avg daily usage in budget projection (td-f08410)
fix(providers): compute billable tokens excluding cached input
test(commands): add task CLI unit tests (td-190775)
refactor: replace WriteString(fmt.Sprintf) with fmt.Fprintf (#41)
fix: serialize provider config with correct YAML key names (fixes #20) (#43)
```

Avoid — also drawn from the existing history, with the conforming rewrite:

| Instead of | Write |
| --- | --- |
| `Bump version to v0.3.4` | `chore: bump version to v0.3.4` |
| `Add pre-commit hook for gofmt/vet/build (#44)` | `build: add pre-commit hook for gofmt/vet/build (#44)` |
| `Fix gofmt formatting issues across codebase` | `style: fix gofmt formatting across codebase` |
| `Update readme` | `docs: update readme` |
| `fix(task)` | `fix(task): guard nil task lookup` |
| `Initial plan` | `chore: add initial plan` |

Merge, revert, `fixup!`, and `squash!` subjects that git writes itself are passed
through unchanged.

## Tooling

Install the hooks and the message template once per clone:

```sh
make install-hooks
```

That symlinks `.git/hooks/pre-commit` and `.git/hooks/commit-msg` to the scripts in
`scripts/`, and points `commit.template` at `.gitmessage.txt` so `git commit` opens with
the format inline.

| Command | Does |
| --- | --- |
| `make install-hooks` | Install both hooks and the commit template |
| `make test-scripts` | Run the validator's own test suite |
| `make lint-commits` | Validate commits on your branch against `origin/main` |
| `scripts/commit-msg.sh <file>` | Validate a single message file |
| `scripts/check-commit-range.sh --base <ref> [<head>]` | Validate a range |

If the hook rejects a message you are confident about, `git commit --no-verify` bypasses
it. CI still checks the commits in the pull request.
