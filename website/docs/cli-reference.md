---
sidebar_position: 8
title: CLI Reference
---

# CLI Reference

## Core Commands

| Command | Description |
|---------|-------------|
| `nightshift setup` | Guided global configuration |
| `nightshift run` | Execute scheduled tasks |
| `nightshift preview` | Show upcoming runs |
| `nightshift budget` | Check token budget status |
| `nightshift task` | Browse and run tasks |
| `nightshift doctor` | Check environment health |
| `nightshift status` | View run history |
| `nightshift logs` | Stream or export logs |
| `nightshift stats` | Token usage statistics |
| `nightshift daemon` | Background scheduler |

## Run Options

`nightshift run` shows a preflight summary before executing, then prompts for confirmation in interactive terminals.

```bash
nightshift run                          # Preflight + confirm + execute (1 project, 1 task)
nightshift run --yes                    # Skip confirmation
nightshift run --dry-run                # Show preflight, don't execute
nightshift run --max-projects 3         # Process up to 3 projects
nightshift run --max-tasks 2            # Run up to 2 tasks per project
nightshift run --random-task            # Pick a random eligible task
nightshift run --ignore-budget          # Bypass budget limits (use with caution)
nightshift run --project ~/code/myapp   # Target specific project (ignores --max-projects)
nightshift run --task lint-fix          # Run specific task (ignores --max-tasks)
```

| Flag | Default | Description |
|------|---------|-------------|
| `--dry-run` | `false` | Show preflight summary and exit without executing |
| `--yes`, `-y` | `false` | Skip confirmation prompt |
| `--max-projects` | `1` | Max projects to process (ignored when `--project` is set) |
| `--max-tasks` | `1` | Max tasks per project (ignored when `--task` is set) |
| `--random-task` | `false` | Pick a random task from eligible tasks instead of the highest-scored one |
| `--ignore-budget` | `false` | Bypass budget checks with a warning |
| `--project`, `-p` | | Target a specific project directory |
| `--task`, `-t` | | Run a specific task by name |

Non-interactive contexts (daemon, cron, piped output) skip the confirmation prompt automatically.

## Preview Options

```bash
nightshift preview                # Default view
nightshift preview -n 3           # Next 3 runs
nightshift preview --long         # Detailed view
nightshift preview --explain      # With prompt previews
nightshift preview --plain        # No pager
nightshift preview --json         # JSON output
nightshift preview --write ./dir  # Write prompts to files
```

## Task Commands

```bash
nightshift task list              # All tasks
nightshift task list --category pr
nightshift task list --cost low --json
nightshift task show lint-fix
nightshift task show lint-fix --prompt-only
nightshift task run lint-fix --provider claude
nightshift task run lint-fix --provider codex --dry-run
```

## Commit Message Commands

```bash
nightshift commit-msg --print-spec              # Print the required format
nightshift commit-msg --check .git/COMMIT_EDITMSG
nightshift commit-msg --fix .git/COMMIT_EDITMSG # Rewrite the file in place
printf 'Fixed the thing.' | nightshift commit-msg --fix -
```

`commit-msg` reads the message from the given file, or from stdin when the
argument is `-` or omitted. Without `--fix` it validates, printing issues as
`file:line: severity: message (rule)` and exiting non-zero if any are errors.

| Flag | Description |
|------|-------------|
| `--check` | Validate only; exit non-zero when the message has errors (the default) |
| `--fix` | Rewrite the message into the canonical format |
| `--print-spec` | Print the commit message format and exit |
| `--quiet` | Suppress issue output; rely on the exit code |

The expected format is Conventional Commits: `type(scope)!: subject`, a blank
line, a body wrapped at 72 columns, and a single trailing block of git
trailers. Messages git generates itself — headers starting with `Merge `,
`Revert "`, `fixup! `, `squash! ` or `amend! ` — are exempt, so merges and
`git rebase --autosquash` are never blocked.

`make install-hooks` installs a `commit-msg` hook that runs
`nightshift commit-msg --check` on every commit; bypass it with
`git commit --no-verify`.

## Budget Commands

```bash
nightshift budget                 # Current status
nightshift budget --provider claude
nightshift budget snapshot --local-only
nightshift budget history -n 10
nightshift budget calibrate
```

## Global Flags

| Flag | Description |
|------|-------------|
| `--verbose` | Verbose output |
| `--provider` | Select provider (claude, codex) |
| `--timeout` | Execution timeout (default 30m) |
