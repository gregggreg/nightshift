# Contributing to Nightshift

Thanks for helping out. This document covers the local setup and the
conventions the project enforces.

## Setup

```bash
git clone https://github.com/marcus/nightshift.git
cd nightshift
make deps
make install-hooks   # one-command setup: git hooks + commit template
make build
make check           # go test + golangci-lint + commit-msg validator tests
```

`make install-hooks` wires up three things:

| What | Where | Purpose |
|---|---|---|
| `scripts/pre-commit.sh` | `.git/hooks/pre-commit` | gofmt, `go vet`, `go build` on staged Go files |
| `scripts/commit-msg.sh` | `.git/hooks/commit-msg` | validates the commit subject (see below) |
| `.gitmessage` | `git config commit.template` | prefills `git commit` with the format guide |

Hooks are opt-in and local — they are never installed automatically. Bypass
either hook in a pinch with `git commit --no-verify`.

## Commit messages

Nightshift uses [Conventional Commits](https://www.conventionalcommits.org/).
This is not a new invention: it is the format the repository already used for
the majority of its history, now written down and enforced going forward.

### Format

```
<type>[(<scope>)][!]: <description>

[optional body, wrapped at 100 chars]

[optional footers]
```

Subject rules, all enforced by `scripts/commit-msg.sh`:

- `<type>` is required and must be one of the types below.
- `<scope>` is optional, in parentheses, lowercase `[a-z0-9._/-]`.
- `!` before the colon marks a breaking change.
- Exactly one space after the colon.
- `<description>` is imperative mood ("add", not "added"/"adds"), is not
  sentence-cased, and does not end with a period. It must start with a letter
  or digit; leading digits and acronyms are fine (`2x faster lookups`,
  `HTTP retry support`, `OAuth token refresh`). What the hook rejects is a
  capital immediately followed by a lowercase letter — `Add budget calibration`.
- The whole subject line is **72 characters or fewer**.
- If a body follows, line 2 must be blank.

### Types

| Type | Use for |
|---|---|
| `feat` | a new user-visible capability |
| `fix` | a bug fix |
| `docs` | documentation only, including `website/` |
| `refactor` | code change that neither fixes a bug nor adds a feature |
| `perf` | a change made to improve performance |
| `test` | adding or correcting tests |
| `build` | build system, `go.mod`, goreleaser, Makefile |
| `ci` | GitHub Actions and other CI configuration |
| `chore` | maintenance that fits nothing else (version bumps, tidying) |
| `style` | formatting only, no behaviour change |
| `revert` | reverting an earlier commit |

### Scopes

Scopes are optional but encouraged. Use the package or area the change lands
in — the names that already appear in the tree:

`config`, `budget`, `scheduler`, `providers`, `tasks`, `orchestrator`,
`commands`, `daemon`, `web`, `docs`, `hooks`, `ci`

### Breaking changes

Mark them both ways — `!` in the subject for scanability, and a
`BREAKING CHANGE:` footer explaining the migration:

```
feat(config)!: drop v1 provider keys

BREAKING CHANGE: `providers.claude.path` is now `providers.claude.data_path`.
Run `nightshift config validate` after upgrading.
```

### Agent-authored commits

Commits produced by a Nightshift agent run must carry these trailers in the
footer so the run can be traced back:

```
Nightshift-Task: <task-id>
Nightshift-Ref: https://github.com/marcus/nightshift
```

### Examples

```
feat(budget): add codex daily token calibration
fix(config): guard nil provider map on merge
docs: document the commit message convention
ci: lint pull request commit messages
feat(api)!: drop legacy budget fields
```

Commits git itself writes or rewrites are exempt from validation: merge
commits, `Revert "..."`, and `fixup!` / `squash!` / `amend!` commits.

### Grandfathered history

History is **not** rewritten. Of the 174 commits on `main` at the time this
convention was written down, 132 (76%) already used a Conventional Commits
prefix and 113 pass the validator as-is; the remaining 61 predate the rules —
mostly merge commits, `Bump version to ...` subjects, and otherwise-valid
subjects that run past 72 characters because a `(#42)` or `(td-abc123)` ref was
appended. Those stay as they are.

Because of this, CI validates **only the commits in a pull request's range**
(`origin/<base>..HEAD`), never the full history. A `git log` on `main` will
still show non-conforming subjects, and that is expected.

Note that GitHub appends ` (#N)` to the subject on squash merge. That happens
server-side, after the hook has run, so a subject that is legal locally can end
up slightly over 72 characters on `main`. Leave a little headroom.

## Pull requests

- PR titles follow the same format as commit subjects — the squash-merge
  subject comes from the PR title.
- Describe *why* in the body, not just what.
- `make check` must pass locally before you push.
- Everything lands on a branch; nothing is committed directly to `main`.

## Code conventions

See [AGENTS.md](AGENTS.md) for the short version:

- **Style**: standard Go — gofmt, `go vet`. Explicit over clever.
- **Errors**: wrap with context, never swallow.
- **Tests**: table-driven, in `_test.go` alongside the code.
- **Logging**: hyper-concise. Include what is needed, minimize words.
