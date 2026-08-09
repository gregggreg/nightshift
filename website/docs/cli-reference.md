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
| `nightshift report` | Read run reports |
| `nightshift busfactor` | Analyze ownership concentration |
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

## Budget Commands

```bash
nightshift budget                 # Current status
nightshift budget --provider claude
nightshift budget snapshot --local-only
nightshift budget history -n 10
nightshift budget calibrate
```

## Reports and Diagnostics

### `nightshift status`

Shows recent run history, or a summary of the current day's activity.

```bash
nightshift status
nightshift status -n 20
nightshift status --today
```

| Flag | Default | Description |
|------|---------|-------------|
| `--last`, `-n` | `5` | Show the last N runs |
| `--today` | `false` | Show today's activity summary instead of run history |

### `nightshift logs`

Reads the Nightshift log files, with filtering by time, level, component, and message text.

```bash
nightshift logs                                  # Last 50 lines
nightshift logs -n 200                           # Last 200 lines
nightshift logs --follow                         # Stream new lines
nightshift logs --level warn                     # Warnings and errors only
nightshift logs --component scheduler            # Filter by component
nightshift logs --match "budget"                 # Filter by message text
nightshift logs --since 2026-01-15 --until 2026-01-16
nightshift logs --summary                        # Counts instead of lines
nightshift logs --export ./nightshift-logs.txt   # Write to a file
```

| Flag | Default | Description |
|------|---------|-------------|
| `--tail`, `-n` | `50` | Number of log lines to show |
| `--follow`, `-f` | `false` | Follow log output as new lines arrive |
| `--export`, `-e` | _(none)_ | Export logs to the given file |
| `--since` | _(none)_ | Start time (`YYYY-MM-DD`, `YYYY-MM-DD HH:MM`, or RFC3339) |
| `--until` | _(none)_ | End time (same formats as `--since`) |
| `--level` | _(all)_ | Minimum log level: `debug`, `info`, `warn`, `error` |
| `--component` | _(all)_ | Filter by component substring |
| `--match` | _(all)_ | Filter by message substring |
| `--summary` | `false` | Show a summary only, without individual lines |
| `--raw` | `false` | Show raw log lines without formatting |
| `--no-color` | `false` | Disable ANSI colors |
| `--path` | _(config)_ | Override the log directory |

### `nightshift stats`

Aggregate token and run statistics across all recorded runs.

```bash
nightshift stats
nightshift stats --period last-7d
nightshift stats --json
```

| Flag | Default | Description |
|------|---------|-------------|
| `--period`, `-p` | `all` | Time period: `all`, `last-7d`, `last-30d`, `last-night` |
| `--json` | `false` | Output as JSON |

### `nightshift report`

Structured reports about what recent runs actually did.

```bash
nightshift report                                # Overview of last night
nightshift report --report tasks                 # Break down by task
nightshift report --report projects --period last-7d
nightshift report --format markdown              # Paste-ready output
nightshift report --format json
nightshift report --since 2026-01-15 --until 2026-01-16
nightshift report --runs 0 --paths               # All runs, with file paths
```

| Flag | Default | Description |
|------|---------|-------------|
| `--report`, `-r` | `overview` | Report type: `overview`, `tasks`, `projects`, `budget`, `raw` |
| `--period`, `-p` | `last-night` | Time period: `last-night`, `last-run`, `last-24h`, `last-7d`, `today`, `yesterday`, `all` |
| `--runs`, `-n` | `3` | Max runs to include (`0` = all) |
| `--since` | _(none)_ | Start time (`YYYY-MM-DD`, `YYYY-MM-DD HH:MM`, or RFC3339) |
| `--until` | _(none)_ | End time (same formats as `--since`) |
| `--format` | `fancy` | Output format: `fancy`, `plain`, `markdown`, `json` |
| `--no-color` | `false` | Disable ANSI colors |
| `--paths` | `false` | Include report and log file paths |
| `--max-items` | `5` | Max highlights shown per run |

### `nightshift busfactor`

Analyzes code ownership concentration from git history. Reports the bus factor
(minimum contributors behind 50% of commits), the Herfindahl index, the Gini
coefficient, and an overall risk level.

The target path can be given either as a positional argument or via `--path`.
When neither is set, the current directory is used.

```bash
nightshift busfactor
nightshift busfactor ~/code/myapp
nightshift busfactor --path ~/code/myapp
nightshift busfactor --since 2026-01-01
nightshift busfactor --file "internal/orchestrator/*"
nightshift busfactor --json
nightshift busfactor --save
```

| Flag | Default | Description |
|------|---------|-------------|
| `--path`, `-p` | _(current directory)_ | Repository or directory path |
| `--file`, `-f` | _(whole repo)_ | Analyze a specific file or pattern |
| `--since` | _(none)_ | Start date (RFC3339 or `YYYY-MM-DD`) |
| `--until` | _(none)_ | End date (RFC3339 or `YYYY-MM-DD`) |
| `--json` | `false` | Output as JSON |
| `--save` | `false` | Save results to the database |
| `--db` | _(config)_ | Database path; uses the configured path when unset |

### `nightshift doctor`

Runs diagnostics against your configuration and environment. It takes no flags.

```bash
nightshift doctor
```

## Global Flags

| Flag | Description |
|------|-------------|
| `--verbose` | Verbose output |
| `--help`, `-h` | Show help for that command |
| `--provider` | Select provider (claude, codex) |
| `--timeout` | Execution timeout (default 30m) |

`--version` / `-v` is registered on the root command only, so it is not accepted by
subcommands:

```bash
nightshift --version
```
