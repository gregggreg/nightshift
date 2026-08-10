# Commit messages

Nightshift uses [Conventional Commits](https://www.conventionalcommits.org/) for
commit subjects. The format is machine-readable, so it can drive the changelog
and release tooling, and it is already what most of this repository's history
looks like.

Tooling lives in `cmd/commitmsg` (the CLI) and `internal/commitmsg` (the rules).
The `commit-msg` hook normalizes what it can and rejects what it cannot fix, and
CI checks the commits a pull request adds.

## Format

```
type(scope)!: subject line

Body paragraph, wrapped at 72 columns. Explain why the change is being
made, not what the diff already shows.

Trailer-Key: value
```

* `type` — required, from the table below.
* `(scope)` — optional, lowercase, the area touched (`budget`, `cli`,
  `providers`, `tasks`, …).
* `!` — optional, marks a breaking change.
* `: ` — a colon *and* a space.
* `subject` — required.

## Types

| Type | Meaning |
| --- | --- |
| `feat` | a user-visible feature |
| `fix` | a bug fix |
| `docs` | documentation only |
| `style` | formatting only, no behaviour change |
| `refactor` | restructuring without behaviour change |
| `perf` | a performance improvement |
| `test` | adding or fixing tests |
| `build` | build system, dependencies, release packaging |
| `ci` | CI configuration and workflows |
| `chore` | maintenance that fits nowhere else |
| `revert` | reverts a previous commit |

## Rules

Subject:

* imperative mood — "add the flag", not "added" or "adds"
* starts lowercase; acronyms (`API`) and identifiers (`README.md`) keep their
  case
* no trailing period
* 72 characters or fewer, including the `type(scope): ` prefix

Body:

* separated from the subject by exactly one blank line
* optional — small changes do not need one
* wrapped at 72 columns; the linter's hard limit is 80, so a slightly long line
  is tolerated rather than rejected

The width limit is not applied to fenced code blocks, indented blocks, trailers,
or lines containing a token (a URL or path) that is itself longer than the
limit.

## Trailers

The final block of `Key: value` lines is a trailer block. It is never rewritten,
reflowed, or width-checked. Nightshift-generated commits carry:

```
Nightshift-Task: commit-normalize
Nightshift-Ref: https://github.com/marcus/nightshift
```

`Co-Authored-By:`, `Signed-off-by:`, `Refs:` and friends work the same way.

## Exemptions

Messages that git itself writes or rewrites are not checked: merge commits
(`Merge …`), reverts (`Revert "…"`), and autosquash messages (`fixup! …`,
`squash! …`).

## Examples

Good:

```
feat(budget): add monthly rollover for unused credit
fix(cli): apply --max-projects after the processed-today filter
docs: README.md gains a hook install section
feat(config)!: rename provider.key to provider.api_key
chore: wire up the commit-msg hook
```

Bad:

```
Fixed the bug.                  → no type; past tense; trailing period
feat:add the flag               → missing space after the colon
feet: add the flag              → "feet" is not an allowed type
feat: Add the flag              → subject starts with a capital
feat(): add the flag            → empty scope
update stuff                    → no type, and says nothing
```

## Tooling

Install the hooks (opt-in, one command):

```bash
make install-hooks
```

That symlinks `scripts/pre-commit.sh` and `scripts/commit-msg.sh` into
`.git/hooks/`. The `commit-msg` hook runs the normalizer and then the linter on
every commit. Bypass it once with `git commit --no-verify`.

Run the tools directly:

```bash
go run ./cmd/commitmsg normalize .git/COMMIT_EDITMSG   # rewrite in place
go run ./cmd/commitmsg lint .git/COMMIT_EDITMSG        # validate one message
echo "feat: add a thing" | go run ./cmd/commitmsg lint # validate stdin
make commit-lint                                       # origin/main..HEAD
make commit-lint RANGE=HEAD~20..HEAD                   # any range
go run ./cmd/commitmsg lint --range HEAD~50..HEAD --report-only
```

The normalizer only fixes mechanical problems — casing, the space after the
colon, trailing periods, whitespace, blank-line placement. It never rewraps or
rewrites prose, so a too-long subject or an unwrapped body is reported by the
linter for a human to fix.

Normalization is idempotent: running it twice produces the same output.

## Scope of enforcement

History is not rewritten and existing commits are not retroactively enforced.
CI (`.github/workflows/commit-lint.yml`) checks only the commits a pull request
adds.
