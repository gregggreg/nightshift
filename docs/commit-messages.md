# Commit message convention

Nightshift uses [Conventional Commits](https://www.conventionalcommits.org/). Roughly
three quarters of the existing history already follows this shape, so this document
codifies current practice rather than introducing a new one.

## Format

```
<type>(<scope>)!: <subject>

<body>

<trailers>
```

- **type** — required, lowercase, from the list below.
- **scope** — optional, lowercase, in parentheses.
- **`!`** — optional, marks a breaking change.
- **subject** — required, imperative mood, no trailing period, soft limit of 72 characters.
- **blank line** — required between the subject and the body.
- **body** — optional, free-form. Explain *why*, not *what*.
- **trailers** — optional, standard git trailers in the final paragraph.

## Types

Derived from the types already in use in this repository, plus the standard set:

| Type | Use for |
| --- | --- |
| `feat` | A new user-facing capability |
| `fix` | A bug fix |
| `docs` | Documentation only |
| `refactor` | Restructuring with no behaviour change |
| `perf` | Performance work |
| `test` | Tests only |
| `build` | Build system, `go.mod`, release packaging |
| `ci` | CI configuration and workflows |
| `chore` | Maintenance that fits nowhere else |
| `style` | Formatting only (`gofmt`, whitespace) |
| `revert` | Reverting an earlier commit |

## Scopes

Scopes are free-form but should match an existing subsystem. Ones already in use:

`cli`, `providers`, `budget`, `tasks`, `commands`, `agents`, `orchestrator`, `config`,
`scheduler`, `reporting`, `projects`, `snapshots`, `security`, `logging`, `integrations`,
`state`, `preview`, `ui`, `ci`.

## Breaking changes

Mark them with `!` before the colon, and explain the migration in the body:

```
feat(config)!: drop the legacy v0.2 schema

Configs written by v0.2 must be migrated with `nightshift config migrate`.
```

A `BREAKING CHANGE:` trailer is also accepted.

## Trailers

Trailers live in the last paragraph, one per line, and are preserved byte-for-byte by
the normalizer. Nightshift automation relies on these:

```
Nightshift-Task: <task-id>
Nightshift-Ref: https://github.com/marcus/nightshift
Co-Authored-By: Name <email@example.com>
```

## Exemptions

These messages are never rewritten or rejected:

- `Merge ...` — merge commits
- `Revert "..."` — git-generated reverts
- `fixup! ...`, `squash! ...`, `amend! ...` — autosquash markers

## Examples

Good:

```
feat(cli): add --dry-run to the run command
fix(budget): apply the nightly cap after the processed-today filter
docs: document the provider calibration workflow
feat(config)!: drop the legacy v0.2 schema
```

Bad:

```
Add pre-commit hook for gofmt/vet/build     # no type prefix
Feat(CLI): Add a flag.                      # uppercase type, trailing period
fix:fixed the thing                         # past tense, missing space
wibble: do a thing                          # unknown type
```

## Tooling

Three dependency-free shell scripts live in `scripts/`:

| Script | Purpose |
| --- | --- |
| `normalize-commit-msg.sh <file>` | Rewrites a message file in place |
| `normalize-commit-msg.sh --check <file>` | Asserts the message is *already* normalized |
| `lint-commit-msg.sh --range <base>..<head>` | Lints every commit in a range |
| `commit-msg.sh` | The git `commit-msg` hook wrapper |

The normalizer trims whitespace, lowercases the type and scope, drops a trailing period,
guarantees the blank second line, and warns (never fails) on an over-length subject. The
body and every trailer are left untouched.

`--check` never rewrites. It rejects any message that the in-place mode *would* rewrite —
so the **Bad** examples above (uppercase type, trailing period, missing blank second line)
all fail the check, not just unknown or missing types. That is what makes
`lint-commit-msg.sh --range` a real gate once `continue-on-error` is dropped from CI.

The normalizer deliberately does **not** strip `#` comment lines from the body. Git runs
its own cleanup *after* the `commit-msg` hook returns, and that cleanup is flow-aware: it
strips comments from editor-authored messages but keeps them for `git commit -m` (where
the cleanup mode is `whitespace`). Removing them in the hook would delete body text that
git would otherwise have preserved. Only the comment block *preceding* the subject and
everything from the scissors line onward are dropped.

### Installing the hook (opt-in)

Hook installation is explicit — nothing is wired up automatically, so no one's workflow
changes without them asking for it:

```
make install-hooks
```

This symlinks both `scripts/pre-commit.sh` and `scripts/commit-msg.sh` into `.git/hooks/`.
It is idempotent; run it as often as you like. To skip the hook for a single commit:

```
git commit --no-verify
```

### CI

The `commit-messages` job in `.github/workflows/ci.yml` lints every commit in the PR range.
It is **non-blocking by default** (`continue-on-error: true`), because the repository has
pre-existing history that predates this convention. To make it enforcing, delete the
`continue-on-error: true` line from that job.

### Tests

```
./scripts/test-normalize-commit-msg.sh
```
