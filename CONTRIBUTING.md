# Contributing to Nightshift

Thanks for helping out. This file covers the mechanics; see
[README.md](README.md) for what Nightshift is and how to run it.

## Getting set up

```sh
go build ./...
make test           # go test ./...
make install-hooks  # opt-in git hooks (pre-commit + commit-msg)
```

`make install-hooks` symlinks the hooks in `scripts/` into `.git/hooks`. It is
explicit on purpose — nothing installs hooks or edits your git config for you.
Remove them with `make uninstall-hooks`.

## Commit messages

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
type(scope)!: description
```

- allowed types: `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`,
  `refactor`, `revert`, `style`, `test`
- imperative mood, no trailing period, 72 characters or fewer
- a body, if present, is separated from the subject by a blank line
- merge, revert, fixup and squash commits are exempt

The full standard, including what the normalizer will and will not rewrite and
when bypassing the hook is legitimate, is in
[docs/commit-messages.md](docs/commit-messages.md).

The `commit-msg` hook fixes safe deviations (trailing period, capitalized type
or leading verb, spacing) in place and rejects anything it cannot fix. The
**Commit Lint** CI job checks every commit in a pull request, so `--no-verify`
defers the problem rather than avoiding it.

Existing history is not rewritten; the standard applies to new commits.

## Before opening a pull request

```sh
make check   # go test ./... + commit message tests + golangci-lint
```

`make test-commit-msg` runs the commit message hook tests on their own. They are
dependency-free POSIX shell and run under `dash`, `bash`, and `zsh`.

## Pull requests

- keep the change focused; one concern per pull request
- update `README.md` and `docs/` when behaviour or configuration changes
- note anything intentionally left out of scope in the pull request description
