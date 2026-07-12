---
sidebar_position: 7
title: Scheduling
---

# Scheduling

Configure exactly one schedule, then run the daemon to execute Nightshift automatically. A schedule uses either a five-field cron expression or a Go duration interval; setting both is invalid.

## Cron or interval

Use cron when work should start at a calendar time. Nightshift accepts five fields: minute, hour, day of month, month, and day of week.

```yaml
schedule:
  cron: "0 2 * * *" # Every day at 2:00 AM
```

Use an interval when work should recur relative to the last scheduled run:

```yaml
schedule:
  interval: "8h"
```

Intervals use Go duration syntax, for example `30m`, `1h`, or `24h`, and must be positive. The interval scheduler's first run is one interval after it starts; neither scheduling mode runs immediately on daemon startup.

## Execution windows

An optional window restricts jobs to a time range. The start is inclusive and the end is exclusive. Windows may cross midnight.

```yaml
schedule:
  cron: "0 * * * *"
  window:
    start: "22:00"
    end: "06:00"
    timezone: "America/Los_Angeles"
```

In this example, Nightshift runs hourly from 22:00 through 05:00 in the specified timezone. If `timezone` is omitted, the daemon's local timezone is used. `start` and `end` must be `HH:MM` values with hours from 0–23 and minutes from 0–59.

For cron schedules, an occurrence outside the window is skipped; the next cron occurrence is evaluated normally. For interval schedules, the next interval that falls outside the window is moved to the next window start.

## Per-run limits

The `schedule` section also supplies defaults for manual `nightshift run` invocations when its matching flag was not explicitly passed:

```yaml
schedule:
  cron: "0 2 * * *"
  max_projects: 3
  max_tasks: 2
```

- `max_projects` limits eligible projects per `nightshift run`; `0` leaves the command's default of one project in effect.
- `max_tasks` limits selected tasks per project; `0` leaves the command's default of one task in effect.
- An explicit `nightshift run --max-projects` or `--max-tasks` flag overrides the corresponding configuration value. `--project` ignores the project limit and `--task` ignores the task limit.

The current daemon loop does not read these two limits: it processes configured projects and selects up to five tasks for each eligible project. Use `nightshift run` when you need these particular limits enforced.

## Daemon lifecycle

The daemon requires either `schedule.cron` or `schedule.interval`.

```bash
nightshift daemon start
nightshift daemon status
nightshift daemon stop
```

`nightshift daemon start` detaches into the background. Use `--foreground` to keep it attached for debugging, or `--timeout 45m` to set the per-agent execution timeout:

```bash
nightshift daemon start --foreground --timeout 45m
```

The daemon writes its PID to `~/.local/share/nightshift/nightshift.pid`. `status` reports the process, configured schedule, and window. `stop` sends `SIGTERM` and waits up to ten seconds before force-stopping a process that has not exited. The daemon also handles `SIGINT` and `SIGTERM` for graceful scheduler shutdown.

## Preview and manual runs

Preview upcoming work without starting a daemon:

```bash
nightshift preview
nightshift preview -n 3
nightshift preview --explain
```

To run once without waiting for the schedule:

```bash
nightshift run --dry-run
nightshift run --yes
nightshift run --max-projects 3 --max-tasks 2
```

In an interactive terminal, `nightshift run` shows a preflight summary and asks for confirmation. Non-interactive runs, including daemon runs, skip that prompt automatically. See [Configuration](/docs/configuration) for the complete YAML layout and [CLI Reference](/docs/cli-reference) for command options.
