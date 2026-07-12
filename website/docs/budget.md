---
sidebar_position: 6
title: Budget
---

# Budget management

Nightshift calculates an allowance for each enabled provider before it selects work. The allowance is based on local usage data, the configured or calibrated weekly budget, and the limits in `budget`.

Use the status command to inspect the resolved budget, usage, reserve, allowance, and any reset times captured in a snapshot:

```bash
nightshift budget
nightshift budget --provider claude
nightshift budget --provider codex
```

The provider must be enabled in [Configuration](/docs/configuration). If a provider has no remaining allowance, Nightshift skips it and tries the next provider in `providers.preference`.

## Configuration

These settings belong under the top-level `budget` key.

| Field | Default | Purpose |
| --- | --- | --- |
| `mode` | `daily` | Allowance model: `daily` or `weekly`. |
| `max_percent` | `75` | Percentage of the available budget that one Nightshift run may use. Valid values are 1–100. |
| `reserve_percent` | `5` | Percentage held back after the allowance calculation. Valid values are 0–100. |
| `aggressive_end_of_week` | `false` | In weekly mode, increases the allowance when two or fewer days remain. |
| `weekly_tokens` | `700000` | Default weekly token budget when there is no provider-specific value or usable calibration. |
| `per_provider` | unset | Weekly token overrides keyed by `claude`, `codex`, or `copilot`. |
| `billing_mode` | `subscription` | `subscription` enables optional calibration; `api` uses configured token limits. |
| `calibrate_enabled` | `true` | Enables subscription-budget inference from snapshots. It is disabled automatically for API billing. |
| `snapshot_interval` | `30m` | How often the daemon collects snapshots. This must be a positive Go duration, such as `30m` or `1h`. |
| `snapshot_retention_days` | `90` | Number of days to retain snapshots. Set `0` to keep them indefinitely. |
| `week_start_day` | `monday` | `monday` or `sunday`; determines how snapshots are grouped for calibration. |
| `db_path` | `~/.local/share/nightshift/nightshift.db` | SQLite database location. |

For example:

```yaml
budget:
  mode: weekly
  max_percent: 60
  reserve_percent: 10
  aggressive_end_of_week: true
  billing_mode: subscription
  calibrate_enabled: true
  snapshot_interval: 30m
  snapshot_retention_days: 90
  week_start_day: monday
  weekly_tokens: 700000
  per_provider:
    claude: 700000
    codex: 500000
```

## Allowance modes

`daily` is the default. Nightshift divides the resolved weekly budget by seven, calculates the unused part of that daily budget, applies `max_percent`, then subtracts the configured reserve and any predicted daytime usage.

`weekly` spreads the unused weekly budget over the days remaining until the provider's reset, then applies `max_percent`, the reserve, and any predicted daytime usage. With `aggressive_end_of_week: true`, the weekly calculation uses a 1× multiplier with two days remaining and a 2× multiplier with one day remaining.

The status output shows the values it used, including the budget source and confidence when calibration is available. `--ignore-budget` on `nightshift run` bypasses these checks; use it deliberately because it can select an otherwise exhausted provider.

## Subscription calibration and snapshots

For subscription accounts, Nightshift can infer a provider's weekly budget from snapshots. A snapshot records local token totals and, when tmux scraping is available, the provider's reported usage percentage. The inference is:

```text
weekly budget = local weekly tokens / (reported percentage / 100)
```

Snapshots with a reported percentage between 10% and 95% and nonzero local tokens are used for the current configured week. Nightshift uses the median after filtering outliers and falls back to the previous week or configured budget when it has no usable current samples.

Capture and inspect snapshots with the `nightshift budget` subcommands:

```bash
nightshift budget snapshot
nightshift budget snapshot --provider claude
nightshift budget snapshot --local-only
nightshift budget history -n 10
nightshift budget history --provider codex --n 20
nightshift budget calibrate
```

`snapshot` reads local usage data for enabled providers. For Claude and Codex, it can also use tmux to run the provider usage command and capture its percentage and reset information. `--local-only`, `calibrate_enabled: false`, and `billing_mode: api` disable that scraping. Copilot snapshots are local-only.

When the daemon is running, it takes a snapshot immediately and then at `snapshot_interval`. It also prunes old rows once every 24 hours. The status and history commands display captured session and weekly reset times when the provider supplied them; a missing reset line simply means no reset time was captured.

## API billing

Use explicit limits for API accounts. API mode turns calibration off and uses `per_provider` where set, otherwise `weekly_tokens`.

```yaml
budget:
  billing_mode: api
  weekly_tokens: 1000000
  per_provider:
    claude: 1000000
    codex: 500000
```

## Troubleshooting

If a budget result has little confidence or falls back to configuration, run `nightshift budget snapshot --provider <provider>` and inspect the output. It identifies missing local data, disabled calibration, unavailable tmux, and provider data-path problems. [Doctor](/docs/cli-reference) also checks recent snapshot health.
