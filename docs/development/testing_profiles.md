# Testing Profiles (Run Modes)

The app supports three **run modes** so you can test different parts of the flow without changing code:

| Mode | Purpose | When to use |
|------|---------|-------------|
| **production** | Realistic flow: conservative entries, full exit logic | Paper/live trading as it would run with real money |
| **exit_testing** | Frequent entries | Test SL, TP, trailing, time stops, and other exit rules with many positions |
| **entry_testing** | Relaxed entry guards | Verify signal → guard → order path; more signals get through |

Merge order is: **`config/algo.yml`** → **profile** (`config/profiles/<run_mode>.yml`) → **DB overrides** (Settings table). Profile and DB overrides use the same deep-merge logic as existing overrides (e.g. indices merged by `key`).

## How to set the mode

1. **In config**: In `config/algo.yml` set top-level `run_mode: exit_testing` (or `entry_testing`, `production`). Default is `production` if omitted.
2. **With ENV**: `RUN_MODE=exit_testing` (or `entry_testing`, `production`). ENV wins over `algo.yml` when present.

Example:

```bash
RUN_MODE=exit_testing ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon
```

After startup, the effective mode is available as `AlgoConfig.run_mode` (e.g. for logging or health).

## What each profile changes

### Production (`config/profiles/production.yml`)

- No overrides. Base `algo.yml` is treated as production-safe. Use this (or omit `run_mode`) for normal paper/live runs.

### Exit testing (`config/profiles/exit_testing.yml`)

- **Indices**: Shorter `cooldown_sec` (e.g. 45s), higher `max_trades_per_day` per index and globally so more entries can open.
- **Risk – time_regimes**: `chop_decay.allow_entries: true` and lower `min_adx` so entries are allowed during lunch.
- **Risk – edge_failure_detector**: More lenient thresholds (e.g. more consecutive SLs before pause, shorter pause) so a few SLs don’t block entries for a long time.
- **trade_limits**: Higher `global_max_trades_per_day`.

Use this when you want many positions so that exit logic (SL, TP, trailing, time stop, etc.) runs often.

### Entry testing (`config/profiles/entry_testing.yml`)

- **Indices**: Shorter cooldown, higher per-index trade limits, lower ADX thresholds so more signals qualify.
- **Risk – time_regimes**: `chop_decay.allow_entries: true`, lower `min_adx`.
- **signals**: `enable_smc_avrz_permission: false`, `enable_smc_decision_alignment: false`, `validation_mode: balanced` so SMC and validation block fewer entries.
- **trade_limits**: Higher `global_max_trades_per_day`.

Use this when you want to confirm that the entry pipeline (signal → guards → order) is working and that entries fire when conditions are met.

## Safety notes

- **Paper vs live** is still controlled by `paper_trading.enabled` and `dhanhq.enable_orders` in `algo.yml` (or DB overrides). Run mode does **not** change paper/live; it only changes entry/exit tuning.
- For real money, use `run_mode: production` (or unset) and keep `paper_trading.enabled: false` and `dhanhq.enable_orders: true` only when you intend to trade live.
- Profile files are under `config/profiles/`. Add or edit YAML there; only the keys you override need to be present (deep-merge with base).

## Adding or changing profiles

1. Add or edit a file `config/profiles/<mode>.yml` with the overrides you want (same structure as `algo.yml`, partial is fine).
2. Set `run_mode: <mode>` in `algo.yml` or `RUN_MODE=<mode>` in the environment.
3. Restart the trading daemon (and any process that uses `AlgoConfig`) so the new profile is loaded.
