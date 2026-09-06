# Commit Conventions

Nightshift uses [Conventional Commits](https://www.conventionalcommits.org/).
The format is enforced locally by an opt-in `commit-msg` hook and in CI for every
commit a pull request adds.

## Format

```text
type(scope)!: summary

Optional body, wrapped at 72 columns.

Optional-Trailer: value
```

- **type** — required, lowercase, one of:
  `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`,
  `style`, `test`
- **scope** — optional, in parentheses. Letters, digits, and `_ . / # -`
  (e.g. `run`, `config`, `.github/workflows`, `#19`).
- **!** — optional, marks a breaking change. Pair it with a
  `BREAKING CHANGE:` footer explaining the migration.
- **summary** — required, imperative mood, starts lowercase (acronyms such as
  `API` keep their case), no trailing period.
- **subject line** — 72 characters or fewer, including the type and scope.
  GitHub appends ` (#123)` when squash-merging, so leaving headroom helps.
- **body** — optional, separated from the subject by exactly one blank line,
  wrapped at 72 columns.
- **footers** — `BREAKING CHANGE: …` and issue references (`Fixes #21`) go last.

### Examples

```text
feat(run): add pause command
fix(config)!: reject unknown provider keys
docs: explain hook installation
ci(.github/workflows): pin action versions
```

## Messages that are never rewritten or rejected

Git writes some subjects itself. Blocking those would break ordinary workflows,
so both the normalizer and the validator pass them through untouched:

- `Merge …` and `Revert "…"`
- `fixup!`, `squash!`, and `amend!` (autosquash)
- `WIP on …` and `index on …` (stashes)
- comment-only messages produced by the commit template (comment lines are
  detected using `core.commentString` / `core.commentChar`, defaulting to `#`)

Under `git commit -v` (or `commit.verbose = true`) git appends a scissors
marker followed by a raw diff:

```text
# ------------------------ >8 ------------------------
diff --git a/main.go b/main.go
```

Git truncates the message at that marker. The scissors line and everything
below it are copied through byte for byte — nothing is moved above the marker
and nothing below it is validated, so the diff never leaks into the commit
body.

## Tooling

| Command | Purpose |
| --- | --- |
| `scripts/normalize-commit-msg.sh <file>` | Rewrites a message file in place |
| `scripts/normalize-commit-msg.sh --infer <file>` | Also prefixes `chore: ` when no type is present |
| `scripts/validate-commit-msg.sh <file>` | Validates a message file |
| `scripts/validate-commit-msg.sh --subject "<text>"` | Validates a single subject line |
| `scripts/install-hooks.sh` (or `make install-hooks`) | Enables the repository hooks |
| `make test-commit-msg` | Runs `tests/commit-msg-test.sh` |

### What the normalizer changes

Normalization is deliberately conservative — it only rewrites what is
mechanically safe:

- trims trailing whitespace and leading/trailing blank lines
- collapses repeated whitespace inside the subject
- lowercases a recognized type and removes spacing around the scope and `!`
- removes a single trailing period from the subject (`...` is preserved)
- lowercases a capitalized first word (`Add x` → `add x`), leaving acronyms and
  mixed-case identifiers alone
- inserts the missing blank line between subject and body, and collapses runs of
  blank lines in the body

It never invents a type. If a subject has no recognized `type:` prefix, the
normalizer leaves it for the validator to report — unless you explicitly pass
`--infer`, which prefixes `chore: `.

## Local setup

```bash
make install-hooks   # git config core.hooksPath .githooks
```

This is opt-in; contributors who skip it are only checked in CI. The
`commit-msg` hook normalizes the message in place first, so most problems are
fixed silently and only genuinely ambiguous ones reject the commit. Bypass a
single commit with `git commit --no-verify`, and disable the hooks entirely with
`git config --unset core.hooksPath`.

## CI

`.github/workflows/commit-lint.yml` runs the shell test suite and validates the
subject of every commit the pull request adds
(`git log --pretty=%s origin/<base>..HEAD`). Commits already on the base branch
are not re-checked, so the pre-Conventional-Commits history stays as it is.
