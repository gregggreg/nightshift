# Contributing to Nightshift

## Commit messages

Nightshift uses [Conventional Commits](https://www.conventionalcommits.org/). The
format was not invented for this document — it is what the existing history
already does, and the tooling below just makes it consistent.

```
<type>(<optional scope>)<optional !>: <lowercase imperative subject>

<optional body, wrapped at 72 columns>

<optional trailers>
```

- **type** — one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
  `build`, `ci`, `chore`, `revert`
- **scope** — optional, lowercase, e.g. `(runner)`, `(tui)`, `(config)`
- **`!`** — marks a breaking change, e.g. `feat(api)!: drop v1 endpoints`
- **subject** — lowercase, imperative ("add", not "adds"/"Added"), no trailing
  period, 72 characters or fewer
- **body** — separated from the subject by a blank line
- **trailers** — last, e.g. `Co-Authored-By:`, `Nightshift-Task:`

### Good

```
feat(runner): add per-task timeout
fix: stop leaking the task context on cancel
docs: document the commit message format
feat(api)!: drop v1 endpoints
```

### Bad

```
Fix: Thing.                  → fix: thing
Update readme                → docs: update readme
feat - add worker pool       → feat: add worker pool
[feat] add worker pool       → feat: add worker pool
feat: Add a really long subject that runs well past seventy-two characters
```

Merge, revert, `fixup!`, `squash!` and `amend!` messages are exempt — they are
passed through untouched by both the hook and CI.

### Install the hook (opt-in)

```
make install-hooks
```

This symlinks `scripts/pre-commit.sh` and `scripts/commit-msg.sh` into
`.git/hooks/`. Nothing installs itself; your git config is only changed when you
run that target.

The `commit-msg` hook first *normalizes* the message — it fixes case, trailing
punctuation, near-miss prefixes (`Fix:`, `feat -`, `[feat]`), missing space
after the colon, blank-line structure, and the blank line git needs before
a trailer block — and then *validates* the result.
Only what cannot be fixed unambiguously (unknown type, empty subject,
over-length subject) blocks the commit, and the error explains the fix.
Normalization is idempotent.

The hook never deletes comment lines. Git already does that itself, *after* the
hook runs and only when it should: an editor-authored message loses its
generated template, while `git commit -m` keeps a body line that happens to
start with `#`. The hook leaves the trailing template block untouched and
respects `core.commentChar`/`core.commentString`, so a body such as
`#123 explains why` survives exactly as it would without the hook. The one
consequence is that a trailing `#` line is assumed to be a template and is not
validated — a missed warning rather than a rejected commit.

### Bypass

```
NORMALIZE_COMMIT_MSG=0 git commit -m "..."   # skip normalize + validate
git commit --no-verify -m "..."              # skip all hooks
```

### How CI enforces it

`.github/workflows/commit-lint.yml` runs on pull requests and validates every
commit subject in the PR range with `scripts/validate-commit-msg.sh`, reporting
all failures at once. It only looks at commits in the PR — existing history is
never rewritten. Fix failures with `git rebase -i <base-sha>` and reword.

### Tooling

| Script | Purpose |
| --- | --- |
| `scripts/normalize-commit-msg.sh <file>` | Rewrite a commit message file in place |
| `scripts/validate-commit-msg.sh [--quiet] [<file>\|-]` | Validate; non-zero on failure |
| `scripts/commit-msg.sh` | The git hook (normalize, then validate) |
| `tests/run-commit-msg-tests.sh` | Test suite (`make test-commit-msg`) |

Both scripts are dependency-free POSIX shell — no Node, no commitlint.

## Code

Run `make check` before opening a PR (tests, lint, and the commit message
tests). See `AGENTS.md` for repository conventions.
