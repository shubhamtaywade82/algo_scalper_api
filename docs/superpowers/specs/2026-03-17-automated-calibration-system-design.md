# Automated Options Calibration System — Design Spec

**Date:** 2026-03-17
**Status:** Approved for implementation
**Branch:** New branch (separate from current `fix/logging-and-job-run-improvements`)
**Related plan:** `docs/superpowers/plans/2026-03-16-algo-config-settings-versioning-performance.md`

---

## Goal

Replace manual rake-driven calibration with an automated weekly pipeline that:
- Fetches ATM and ATM±1 options data per index with correct expiry logic (NIFTY=Thursday, SENSEX=Friday)
- Detects regime shifts in market behaviour and auto-recalibrates from a recent window
- Generates a full `algo.yml`-compatible config patch covering all trailing and exit parameters
- Proposes the patch via Telegram + REST API, with human approval before applying
- Persists calibration history to enable regime detection and forward-testing of config versions
- Integrates cleanly with the planned `algo_config_versions` system (versioning plan) without requiring it

---

## Architecture

### Approach: Composition layer (Option B)

Keep `HistoricalCalibrationEngine` and the rake task untouched. Build a new job-facing orchestrator (`AutoCalibrator`) that reuses `HistoricalCalibrationEngine` for core stat math while adding multi-strike fetching, expiry awareness, regime detection, and config patch generation.

```
WeeklyCalibrationJob (Solid Queue, Sunday 6AM IST)
  → Options::AutoCalibrator.call(symbol:, weeks:)
      → Options::ExpiryCalendar.windows(symbol, weeks)
      → DhanHQ fetch: ATM, ATM+1, ATM-1 CE/PE (6 series per expiry window)
      → HistoricalCalibrationEngine × 3 (one per strike)
      → Options::StrikeAggregator.combine(atm, otm1, otm2)
      → Options::RegimeDetector.check(symbol, recent_stats, history)
      → Options::CalibrationConfigPatchBuilder.build(combined_stats, symbol)
      → CalibrationRun.create!(...)
      → CalibrationRun#propose_config!  (settings table today, AlgoConfigVersion later)
      → CalibrationNotifier.notify(result)
```

The rake task (`options:historical_behaviour`) is unchanged. `options:calibrate_from_csv` and `options:calibrate_batch` are unchanged.

---

## Data Layer

### `calibration_runs` table (new)

| Column | Type | Notes |
|--------|------|-------|
| `id` | integer pk | |
| `symbol` | string | `'NIFTY'` \| `'SENSEX'` |
| `weeks_analyzed` | integer | 52 (routine) or 8 (regime-shift recalibration) |
| `strike_mode` | string | `'atm_plus_minus'` \| `'atm_only'` |
| `raw_stats` | jsonb | CE/PE aggregates per strike (ATM, OTM1, OTM2) |
| `proposed_patch` | jsonb | Full algo.yml-compatible patch hash |
| `is_regime_shift` | boolean | True if triggered by regime detection |
| `regime_reason` | string | Human-readable description of shift |
| `applied_at` | datetime | Null = pending, set = applied |
| `applied_by` | string | `'api'` \| `'telegram'` \| `'auto'` |
| `created_at` / `updated_at` | datetime | |

Indexes: `symbol + created_at` (for regime detection queries), `applied_at` (for pending run queries).

---

## New Services

### `Options::ExpiryCalendar`

Replaces the `last_thursday` helper baked into the rake task. Maps each symbol to its expiry weekday and generates weekly windows.

```ruby
Options::ExpiryCalendar.windows(symbol: 'SENSEX', weeks: 52)
# → [{expiry: <Friday>, from: <expiry-6>, to: <expiry>}, ...]

Options::ExpiryCalendar.windows(symbol: 'NIFTY', weeks: 52)
# → [{expiry: <Thursday>, from: <expiry-6>, to: <expiry>}, ...]
```

**Expiry day map:**
```ruby
EXPIRY_WEEKDAY = { 'NIFTY' => 4, 'SENSEX' => 5 }.freeze  # Thu=4, Fri=5
```

Extensible: adding a new symbol requires one line in the constant. Raises `ArgumentError` for unknown symbols.

---

### `Options::AutoCalibrator`

Orchestrates the full pipeline. Pure coordinator — no I/O logic, delegates to focused collaborators.

```ruby
result = Options::AutoCalibrator.call(symbol: 'SENSEX', weeks: 52)
# => { run: CalibrationRun, regime_shift: false, patch: {...} }
```

**Responsibilities:**
1. Call `ExpiryCalendar.windows`
2. Fetch ATM, ATM+1, ATM-1 CE/PE data from DhanHQ for each window (6 series)
3. Feed each strike's rows to `HistoricalCalibrationEngine` and collect results
4. Pass all three results to `StrikeAggregator`
5. Pass aggregated stats to `RegimeDetector`
6. If regime shift: re-run steps 2–5 with `weeks: 8`
7. Pass final stats to `CalibrationConfigPatchBuilder`
8. Create `CalibrationRun` record
9. Call `run.propose_config!`
10. Return result hash

**ATM±1 fetch strategy:** The DhanHQ `ExpiredOptionsData` API `strike:` param is checked for OTM offset support. If the gem exposes `'OTM1'` / `'OTM2'` values, use them directly. If not, calculate explicit strike prices from spot price at window open and fetch by strike number. `AutoCalibrator` handles this internally; no external consumer needs to know.

---

### `Options::StrikeAggregator`

Combines ATM, OTM1, OTM2 stat hashes into a single weighted profile. Pure computation, no I/O.

**Weights:**
- ATM → 50% (most frequently traded)
- OTM1 → 25% (ATM+1 CE / ATM-1 PE — the directional side)
- OTM2 → 25% (opposite side)

Operates on the output of `HistoricalCalibrationEngine#call` (the `ce` and `pe` leg summaries). Produces the same shape as `HistoricalCalibrationEngine#call` so `CalibrationConfigPatchBuilder` has a stable input interface regardless of single-strike or multi-strike mode.

---

### `Options::RegimeDetector`

Compares the most recent 4-week rolling window of `CalibrationRun` stats against the full history for the same symbol.

**Trigger condition:** Regime shift declared if **any** of the following exceed 1.5 standard deviations from the historical mean:
- `post_peak_retrace` average
- `max_loss_pct` average
- OC standard deviation (volatility of outcomes)

**On shift:**
- `AutoCalibrator` calls itself again with `weeks: 8`
- The 8-week result becomes the proposed patch
- `is_regime_shift: true`, `regime_reason:` populated with which metric triggered and by how much

**Minimum history:** Requires at least 12 `CalibrationRun` records for the symbol before regime detection is active. Below 12, always returns `shift: false` (insufficient baseline).

---

### `Options::CalibrationConfigPatchBuilder`

Translates weighted calibration stats into the exact config structure `algo.yml` uses. Only outputs keys where the derived value differs from the current `AlgoConfig.fetch` value by more than 10% — keeps the patch minimal.

**Input:** combined stats from `StrikeAggregator` (`avg_gain`, `avg_retrace_abs`, `avg_loss_abs`, `avg_oc`, `oc_stddev`, sessions)
**Output:** nested hash ready for `deep_merge` into `algo_config_overrides`

**Derivation formulas** (all clamped to safe ranges):

| Config key | Formula | Clamp |
|---|---|---|
| `risk.percentage_pnl_exit.target_pct` | `avg_gain × 0.45 / 100` | 0.08..0.35 |
| `risk.trailing.activation_pct` | `avg_gain × 0.25 / 100` | 0.020..0.08 |
| `risk.trailing.drawdown_pct` | `avg_retrace_abs × 0.80 / 100` | 0.015..0.060 |
| `institutional_trailing.early_trigger` | `activation_pct × 0.85` | 0.020..0.06 |
| `institutional_trailing.breakeven_trigger` | `activation_pct × 1.5` | 0.040..0.12 |
| `institutional_trailing.activation_trigger` | `target_pct × 0.55` | 0.08..0.20 |
| `institutional_trailing.trailing_distance` | `drawdown_pct × 1.1` | 0.030..0.12 |
| `institutional_trailing.adaptive_drawdown` | `[td, td×0.9, td×0.75, td×0.6]` | each ≥ 0.020 |
| `risk.profit_floor.lock_pct` | `avg_gain × 0.20 / 100` | 0.06..0.15 |
| `risk.profit_floor.trail_pct` | `1.0 - (avg_retrace_abs × 0.8 / 100)` | 0.55..0.92 |
| `risk.time_stop.trend.{symbol}` | session-aware (from existing logic) | 6..30 min |

`institutional_trailing` is nested under the symbol key (`:nifty` or `:sensex`).

`early_sl_offset` is not derived from stats — it remains at its current configured value (insufficient data to derive a meaningful stop offset from historical candles alone).

---

## Job

### `WeeklyCalibrationJob`

```ruby
class WeeklyCalibrationJob < ApplicationJob
  queue_as :default

  def perform(symbol: nil, weeks: 52)
    symbols = symbol ? [symbol.upcase] : %w[NIFTY SENSEX]
    symbols.each do |sym|
      result = Options::AutoCalibrator.call(symbol: sym, weeks: weeks)
      CalibrationNotifier.notify(result)
    end
  end
end
```

Processes symbols sequentially to respect DhanHQ rate limits. Each symbol is independently rescued — a NIFTY failure does not prevent SENSEX from running.

### `config/recurring.yml` addition

```yaml
weekly_options_calibration:
  class: WeeklyCalibrationJob
  schedule: every Sunday at 6:00 am Asia/Kolkata
  queue: default
```

---

## Notifications

### `CalibrationNotifier`

Thin wrapper around `TelegramNotifier`. Sends two messages per symbol.

**Message 1 — Summary:**
```
📊 SENSEX Weekly Calibration — 2026-03-22

CE ATM  MaxGain: +18.4%  Retrace: -14.2%  OC: +3.1%
CE OTM1 MaxGain: +24.1%  Retrace: -19.8%  OC: -1.2%
PE ATM  MaxGain: +16.9%  Retrace: -13.1%  OC: -0.4%

Score: 4.2 (balanced)  Confidence: high (n=52)
⚠️ REGIME SHIFT — retrace jumped +18% vs baseline (last 4 wks)
↳ Patch generated from 8-week window only
```

**Message 2 — Patch + apply instructions (changed keys only):**
```
📋 Proposed patch (run_id: 47):

trailing.activation_pct:             0.025 → 0.030
institutional_trailing.sensex:
  breakeven_trigger:                 0.050 → 0.045
  trailing_distance:                 0.055 → 0.062

To apply:
  POST /api/calibration_runs/47/apply
```

Only keys that differ from current config by >10% are shown. No patch shown if nothing changed significantly.

---

## API

### Routes

```ruby
namespace :api do
  resources :calibration_runs, only: [:index, :show] do
    member { post :apply }
  end
end
```

### Endpoints

| Method | Path | Action |
|--------|------|--------|
| `GET` | `/api/calibration_runs` | List recent runs (symbol filter, pending/applied filter) |
| `GET` | `/api/calibration_runs/:id` | Full patch + stats for one run |
| `POST` | `/api/calibration_runs/:id/apply` | Apply patch to settings, set `applied_at` |

---

## `CalibrationRun` Model Methods

### `propose_config!`

Writes a pending proposal. Versioning-bridge: routes to `AlgoConfigVersion` when that system exists, otherwise writes to `settings` table.

```ruby
def propose_config!
  if defined?(AlgoConfigVersion)
    AlgoConfigVersion.create!(
      name: "calibration-#{symbol.downcase}-#{created_at.strftime('%Y%m%d')}",
      overrides: proposed_patch,
      source: 'calibration',
      calibration_run_id: id
    )
  else
    Setting.upsert(
      { key: "calibration_proposal_#{symbol.downcase}", value: proposed_patch.to_json },
      unique_by: :key
    )
  end
end
```

### `apply!(applied_by: 'api')`

Deep-merges `proposed_patch` into `algo_config_overrides` in the `settings` table. Trading daemon picks up the change within 30 seconds via `AlgoConfig`'s existing cache TTL.

```ruby
def apply!(applied_by: 'api')
  current = JSON.parse(Setting.find_by(key: 'algo_config_overrides')&.value || '{}')
  merged  = current.deep_merge(proposed_patch)
  Setting.upsert({ key: 'algo_config_overrides', value: merged.to_json }, unique_by: :key)
  update!(applied_at: Time.current, applied_by: applied_by)
end
```

When the `algo_config_versions` branch lands: `apply!` creates an `AlgoConfigVersion` record instead. `CalibrationRun` gains a `config_version_id` FK at that point. No controller or job changes needed.

---

## Files to Create / Modify

### New files

| Path | Purpose |
|------|---------|
| `app/models/calibration_run.rb` | Model + `propose_config!` + `apply!` |
| `db/migrate/TIMESTAMP_create_calibration_runs.rb` | Migration |
| `app/services/options/auto_calibrator.rb` | Orchestrator |
| `app/services/options/expiry_calendar.rb` | Per-index expiry windows |
| `app/services/options/strike_aggregator.rb` | Weighted ATM/OTM1/OTM2 combine |
| `app/services/options/regime_detector.rb` | Regime shift detection |
| `app/services/options/calibration_config_patch_builder.rb` | Full config patch derivation |
| `app/services/options/calibration_notifier.rb` | Telegram formatting |
| `app/jobs/weekly_calibration_job.rb` | Solid Queue job |
| `app/controllers/api/calibration_runs_controller.rb` | index / show / apply |
| `spec/models/calibration_run_spec.rb` | |
| `spec/services/options/auto_calibrator_spec.rb` | |
| `spec/services/options/expiry_calendar_spec.rb` | |
| `spec/services/options/strike_aggregator_spec.rb` | |
| `spec/services/options/regime_detector_spec.rb` | |
| `spec/services/options/calibration_config_patch_builder_spec.rb` | |
| `spec/jobs/weekly_calibration_job_spec.rb` | |

### Modified files

| Path | Change |
|------|--------|
| `config/recurring.yml` | Add `weekly_options_calibration` schedule |
| `config/routes.rb` | Add `calibration_runs` resource |

### Unchanged files

| Path | Reason |
|------|--------|
| `lib/tasks/historical_options.rake` | Rake task stays for manual use |
| `lib/tasks/options_calibration.rake` | Rake task stays for manual use |
| `app/services/options/historical_calibration_engine.rb` | Reused as-is by `AutoCalibrator` |

---

## Error Handling

- **DhanHQ fetch failure for one strike:** Log warning, proceed with available strikes (ATM-only if OTM fetch fails). Note `strike_mode: 'atm_only'` in the run record.
- **All fetches fail for a symbol:** Log error, skip `CalibrationRun` creation, send Telegram error message.
- **Regime detector has insufficient history:** Skip detection silently, proceed with full-window calibration.
- **Telegram send failure:** Log error, do not retry — the run record exists and is accessible via API.
- **Apply fails (settings write error):** Raise, return 500 from API. `applied_at` remains null — run stays in pending state.

---

## Testing Strategy

- `ExpiryCalendar`: unit test Thursday/Friday logic, edge cases (run on expiry day itself, run mid-week)
- `StrikeAggregator`: unit test weighted average with known inputs
- `RegimeDetector`: unit test with fixture `CalibrationRun` records; test below-threshold and above-threshold cases; test insufficient-history guard
- `CalibrationConfigPatchBuilder`: unit test each formula with known stats; test clamp boundaries; test 10% change filter
- `AutoCalibrator`: integration spec with stubbed DhanHQ and stubbed sub-services
- `WeeklyCalibrationJob`: test `perform` with both `symbol:` arg and nil (both symbols)
- `CalibrationRun`: unit test `apply!` deep-merge behaviour; test `propose_config!` branching logic

All DhanHQ calls stubbed in specs via WebMock — no live API calls in tests.

---

## Compatibility Notes

- **Pre-versioning:** `propose_config!` writes to `settings` table. `apply!` deep-merges into `algo_config_overrides`. Works today.
- **Post-versioning:** When `AlgoConfigVersion` is defined, `propose_config!` creates a version record instead. `CalibrationRun` gains a `config_version_id` FK in a follow-up migration. The `apply!` method routes through `AlgoConfigVersion#activate`. No controller or job changes.
- **Rake task:** Never modified by this feature. Continues to use `HistoricalCalibrationEngine` directly.
