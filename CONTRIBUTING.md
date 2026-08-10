# Contributing to Nightshift

Thanks for helping out. This is a short guide; the README covers installation
and configuration, and `docs/` covers individual subsystems.

## Getting set up

```bash
go build ./...       # or: make build
make test            # go test ./...
make lint            # golangci-lint, if installed
make install-hooks   # opt-in git hooks (recommended)
```

`make install-hooks` symlinks the repo's hooks into `.git/hooks/`:

* **pre-commit** — gofmt, `go vet`, `go build` on staged Go files
* **commit-msg** — normalizes and validates the commit message

Nothing is installed automatically; run the command when you want the hooks.
Bypass them once with `git commit --no-verify`.

## Commit messages

Nightshift uses [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): subject line

Optional body, wrapped at 72 columns (the linter's hard limit is 80).

Optional-Trailer: value
```

Allowed types are `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore`, and `revert`. Subjects are imperative, lowercase, have
no trailing period, and stay within 72 characters.

The full standard, with examples and the exact rules the linter enforces, is in
[docs/commit-messages.md](docs/commit-messages.md).

Check your messages before pushing:

```bash
make commit-lint                      # origin/main..HEAD
make commit-lint RANGE=HEAD~20..HEAD  # any range
```

CI runs the same check over the commits a pull request adds. Existing history is
not retroactively enforced.

## Pull requests

* Keep changes focused; separate refactors from behaviour changes.
* Add or update tests for behaviour you change — `make test` must pass.
* Run `gofmt -w .` (the pre-commit hook checks this).
* Update the docs when you change user-visible behaviour.
