# Commit Messages

Nightshift uses [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
for commit subjects. The format is machine-parseable, which keeps the door open
for generated changelogs and release notes, and it is already what most of this
repository's history looks like.

Two things enforce it, and both are opt-in or advisory rather than magic:

- a local `commit-msg` hook that normalizes what it safely can and rejects what
  it cannot (`make install-hooks`)
- a CI job that validates every commit in a pull request
  (`.github/workflows/commit-lint.yml`)

Existing history is **not** rewritten. The standard applies going forward.

## The format

```
type(scope)!: description

Optional body, wrapped at 72 columns.

Trailer-Key: value
```

Rules:

| Rule | Detail |
|------|--------|
| Type | One of `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`. Lowercase. |
| Scope | Optional, in parentheses, lowercase: `feat(runner)`, `fix(config)`. |
| Breaking | Optional `!` before the colon: `feat(config)!: drop the legacy schema`. |
| Separator | Exactly one space after the colon. |
| Description | Imperative mood ("add", not "added" or "adds"). No trailing period. |
| Subject length | 72 characters or fewer, including the type prefix. A trailing ` (#123)` that GitHub appends on squash merge is not counted. |
| Body | Optional. Separated from the subject by one blank line. |
| Trailers | Last, one per line: `Co-Authored-By:`, `Nightshift-Task:`, and so on. |

The allowed type list is derived from the types this repository's own history
already uses (`feat`, `fix`, `docs`, `chore`, `test`, `refactor`) plus the rest
of the standard Conventional Commits set, so the vocabulary is not artificially
narrow.

### Exempt commits

Commits git generates or rewrites itself are never normalized and never
rejected:

- `Merge ...`
- `Revert "..."`
- `fixup! ...`, `squash! ...`, `amend! ...`

## Examples

Good:

```
feat(runner): add a per-provider retry budget
fix: guard against a nil provider map
docs: document the commit message standard
refactor(config)!: drop the v1 schema loader
chore: bump golangci-lint to v1.62
```

Rejected, and why:

| Subject | Problem |
|---------|---------|
| `Update the makefile` | No type prefix. |
| `chores: tidy the makefile` | `chores` is not an allowed type. |
| `Fix: guard against a nil provider` | Type must be lowercase (the hook fixes this for you). |
| `fix:guard against a nil provider` | Missing space after the colon (the hook fixes this for you). |
| `fix: guard against a nil provider.` | Trailing period (the hook fixes this for you). |
| `feat: <73+ characters>` | Subject exceeds 72 characters. |
| subject immediately followed by body | Missing blank line after the subject. |

## What the normalizer will and will not do

`scripts/normalize-commit-msg.sh` is deliberately conservative. It applies only
mechanical fixes it can make with certainty:

- strips trailing whitespace from the subject
- strips trailing periods from the subject
- lowercases a recognized type token (`Fix:` → `fix:`)
- inserts the missing space after the colon (`fix:add x` → `fix: add x`)
- lowercases the first word of the description **only** when that word is a
  known imperative verb (`fix: Add x` → `fix: add x`)
- ensures exactly one blank line between the subject and the body

It will not:

- touch the body, interior blank lines, or trailers — those are copied verbatim
- guess a type for a subject that has none
- lowercase a leading word it does not recognize, so `docs: Nightshift now …`
  keeps its proper noun
- edit merge, revert, fixup or squash commits

When it cannot parse a subject confidently it leaves the message alone and lets
`scripts/validate-commit-msg.sh` explain the problem. The normalizer can never
turn a valid message into an invalid one.

## Installing the hook

Hook installation is explicit. Nothing changes your git configuration on clone,
build, or test.

```sh
make install-hooks     # installs .git/hooks/pre-commit and .git/hooks/commit-msg
make uninstall-hooks   # removes both
```

Both hooks are symlinks into `scripts/`, so they track the checked-out branch.

## Bypassing the hook

```sh
git commit --no-verify -m "…"
```

Legitimate reasons to bypass:

- you are mid-rebase or scripting a mechanical history operation
- a vendored or generated commit message must be preserved byte-for-byte
- the hook itself is broken and you are committing the fix

Bypassing the local hook does not bypass CI. The Commit Lint job validates every
commit in a pull request, so a bypassed commit still has to be reworded (with
`git commit --amend` or an interactive rebase) before the pull request is
mergeable.

## Files

| Path | Purpose |
|------|---------|
| `scripts/commit-msg-lib.sh` | Shared type list, limits, and helpers. |
| `scripts/normalize-commit-msg.sh` | In-place safe normalization of a message file. |
| `scripts/validate-commit-msg.sh` | Validation; accepts a file path or `-` for stdin. |
| `scripts/commit-msg.sh` | The hook: normalize, then validate. |
| `scripts/tests/commit-msg.test.sh` | Shell tests (`make test-commit-msg`). |
| `.github/workflows/commit-lint.yml` | CI validation of every commit in a PR. |

Everything is dependency-free POSIX shell — no Node, no commitlint, no husky.
The tests run under `dash`, `bash`, and `zsh`.
