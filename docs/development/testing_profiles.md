# Testing Profiles (historical)

> **Note:** Separate run profiles (`production` / `exit_testing` / `entry_testing`),
> `RUN_MODE`, and `config/profiles/*.yml` were **removed**. Effective configuration is
> **`config/algo.yml`** deep-merged with DB `algo_config_overrides` only.

| Mode | Purpose | When to use |
|------|---------|-------------|
| **production** | Full guards active, conservative entries | Paper/live trading as it would run with real money |
| **exit_testing** | Frequent entries (bypasses most entry guards) | Test SL, TP, trailing, time stops, and other exit rules with many positions |
| **entry_testing** | Relaxed entry guards | Verify signal → guard → order path; more signals get through |

Merge order: **`config/algo.yml`** → **profile** (`config/profiles/<run_mode>.yml`) → **DB overrides** (Settings table). Profile and DB overrides use the same deep-merge logic as existing overrides.

**Current default:** `run_mode: exit_testing` in `config/algo.yml`.

---

## How to Set the Mode

1. **In config**: Set top-level `run_mode: exit_testing` (or `entry_testing`, `production`) in `config/algo.yml`. Default is `production` if omitted.
2. **With ENV**: `RUN_MODE=exit_testing` (or `entry_testing`, `production`). ENV wins over `algo.yml` when present.

```bash
# Start in exit testing mode
RUN_MODE=exit_testing ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon

# Start in entry testing mode
RUN_MODE=entry_testing ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon

# Start in production mode
RUN_MODE=production ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon

# Check active mode in console
AlgoConfig.run_mode  # → "exit_testing"
```

---

## What Each Profile Changes

### Production (`config/profiles/production.yml`)

No overrides. Base `config/algo.yml` is treated as production-safe. Use this (or omit `run_mode`) for normal paper/live runs.

### Exit Testing (`config/profiles/exit_testing.yml`)

Changes to generate **many entries** so that exit logic runs frequently:

- **Indices**: Shorter `cooldown_sec` (e.g. 45s), higher `max_trades_per_day` per index and globally
- **Risk – time_regimes**: `chop_decay.allow_entries: true` and lower `min_adx` so entries allowed during S3 (11:30-13:45)
- **Risk – edge_failure_detector**: More lenient thresholds (more consecutive SLs before pause, shorter pause) so a few SLs don't block entries for a long time
- **trade_limits**: Higher `global_max_trades_per_day`
- **Signal::Engine**: Forces `supertrend_adx` strategy on `1m` timeframe, no confirmation, bypasses most quality gates

**Use this when:** Testing that SL, TP, trailing, time stops, profit floor, structure invalidation, and other exit rules trigger correctly.

### Entry Testing (`config/profiles/entry_testing.yml`)

Changes to let more signals pass through the pipeline:

- **Indices**: Shorter cooldown, higher per-index trade limits, lower ADX thresholds
- **Risk – time_regimes**: `chop_decay.allow_entries: true`, lower `min_adx`
- **signals**: `enable_smc_avrz_permission: false`, `enable_smc_decision_alignment: false`, `validation_mode: balanced` — SMC and validation block fewer entries
- **trade_limits**: Higher `global_max_trades_per_day`

**Use this when:** Confirming that the entry pipeline (signal → guards → order) is working and entries fire when conditions are met.

---

## Signal::Engine Behavior by Mode

| Aspect | production | exit_testing | entry_testing |
|--------|-----------|-------------|---------------|
| entry_primary | from config | `supertrend_adx` (forced) | from config |
| primary_tf | from config | `1m` (forced) | from config |
| confirmation_tf | from config | disabled | from config |
| quality gates | full | most bypassed | relaxed |
| SMC gating | enabled | bypassed | disabled |

---

## Safety Notes

- **Paper vs live** is still controlled by `paper_trading.enabled` in `algo.yml` (and `dhanhq.enable_orders` + `PLACE_ORDER` env var for live). Run mode does **not** change paper/live — it only changes entry/exit tuning.
- For real money, use `run_mode: production` and `paper_trading.enabled: false` with `PLACE_ORDER=true` only when intentionally trading live.
- `exit_testing` and `entry_testing` are designed for paper mode only. Do not use them in live trading without careful review of what guards are bypassed.

---

## Adding or Changing Profiles

1. Add or edit a file `config/profiles/<mode>.yml` with the overrides you want (same structure as `algo.yml`, partial is fine — only the keys you override need to be present; deep-merge applies).
2. Set `run_mode: <mode>` in `algo.yml` or `RUN_MODE=<mode>` in the environment.
3. Restart the trading daemon (and any process that uses `AlgoConfig`) so the new profile is loaded.

```yaml
# Example: config/profiles/my_custom_mode.yml
indices:
  - key: NIFTY
    cooldown_sec: 30
    # only override what you need

trade_limits:
  global_max_trades_per_day: 20
```

---

## Profile Files Location

```
config/profiles/
  production.yml      # empty / no overrides
  exit_testing.yml    # frequent entries for exit testing
  entry_testing.yml   # relaxed guards for entry testing
```
