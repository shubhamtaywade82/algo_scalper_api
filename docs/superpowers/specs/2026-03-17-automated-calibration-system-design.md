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
      → CalibrationRun#propose_config!  (no-op pre-versioning; AlgoConfigVersion post-versioning)
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
EXPIRY_WEEKDAY = { 'NIFTY' => 4, 'SENSEX' => 5 }.freeze  # Thu=4, Fri=5 (Date#wday)
```

Extensible: adding a new symbol requires one line in the constant. Raises `ArgumentError` for unknown symbols.

---

### `Options::AutoCalibrator`

Orchestrates the full pipeline. Pure coordinator — no I/O logic, delegates to focused collaborators.

```ruby
result = Options::AutoCalibrator.call(symbol: 'SENSEX', weeks: 52)
# => { run: CalibrationRun, regime_shift: false, patch: {...} }
# => nil if all DhanHQ fetches fail (AutoCalibrator does not raise)
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

**`AutoCalibrator.call` never raises.** All internal errors are rescued, logged, and surfaced as a nil return or a partial result with `error:` key. This allows `WeeklyCalibrationJob` to rescue per-symbol without worrying about internal failure modes.

**Engine output extraction:** `HistoricalCalibrationEngine#call` returns a rich hash (`{ symbol:, row_count:, ce:, pe:, combined:, objective:, profiles:, confidence:, warnings:, suggested_patch: }`). `AutoCalibrator` extracts only `result[:ce]` and `result[:pe]` from each engine call before passing them to `StrikeAggregator`.

**ATM±1 fetch strategy:** The DhanHQ `ExpiredOptionsData` API `strike:` param is checked for OTM offset support. If the gem exposes `'OTM1'` / `'OTM2'` values, use them directly. If not, calculate explicit strike prices from spot price at window open and fetch by strike number. `AutoCalibrator` handles this internally; no external consumer needs to know.

---

### `Options::StrikeAggregator`

Combines ATM, OTM1, OTM2 stat hashes into a single weighted profile. Pure computation, no I/O.

**Strike offset convention:**
- `OTM1` = one strike OTM from spot in the directional sense: ATM+1 for CE legs, ATM-1 for PE legs
- `OTM2` = one strike OTM in the opposite direction: ATM-1 for CE legs, ATM+1 for PE legs

`AutoCalibrator` fetches and labels strikes accordingly before passing to `StrikeAggregator`. The aggregator receives pre-labelled stat hashes and applies weights without needing to know strike numbers.

**Weights:**
- ATM → 50% (most frequently traded)
- OTM1 → 25% (directional OTM — what the system actually buys)
- OTM2 → 25% (opposite side — for risk calibration)

Operates on the output of `HistoricalCalibrationEngine#call` (the `ce` and `pe` leg summaries). Produces the same shape as `HistoricalCalibrationEngine#call` so `CalibrationConfigPatchBuilder` has a stable input interface regardless of single-strike or multi-strike mode.

---

### `Options::RegimeDetector`

Compares the most recent 4-week rolling window of `CalibrationRun` stats against the full history for the same symbol.

**Input stat keys (from `StrikeAggregator` output, matching `HistoricalCalibrationEngine` output shape):**
- `avg_retrace_abs` — average post-peak retracement magnitude
- `avg_loss_abs` — average max drawdown from entry
- `oc_stddev` — standard deviation of open-to-close % (outcome volatility)

**Trigger condition:** Regime shift declared if **any** of the above exceed 1.5 standard deviations from the historical mean across all prior `CalibrationRun` records for the symbol.

**On shift:**
- `AutoCalibrator` calls itself again with `weeks: 8`
- The 8-week result becomes the proposed patch
- `is_regime_shift: true`, `regime_reason:` populated with which metric triggered and by how much (e.g. `"avg_retrace_abs: 14.2% → 31.8% (+1.8σ)"`)

**Minimum history:** Requires at least 12 `CalibrationRun` records for the symbol before regime detection is active. Below 12, always returns `shift: false` (insufficient baseline).

---

### `Options::CalibrationConfigPatchBuilder`

Translates weighted calibration stats into the exact config structure `algo.yml` uses. Only outputs keys where the derived value differs from the current `AlgoConfig.fetch` value by more than 10% — keeps the patch minimal.

**Input:** combined stats from `StrikeAggregator` (`avg_gain`, `avg_retrace_abs`, `avg_loss_abs`, `avg_oc`, `oc_stddev`, sessions)
**Output:** nested hash with **string keys** (call `.deep_stringify_keys` before returning) — required for correct JSON round-trip through `calibration_runs.proposed_patch` (JSONB) and the `apply!` deep-merge path

**Derivation formulas** (all clamped to safe ranges):

| Config key | Formula | Clamp | Note |
|---|---|---|---|
| `risk.percentage_pnl_exit.target_pct` | `avg_gain × 0.45 / 100` | 0.08..0.35 | |
| `risk.trailing.activation_pct` | `avg_gain × 0.25 / 100` | 0.020..0.08 | |
| `risk.trailing.drawdown_pct` | `avg_retrace_abs × 0.80 / 100` | 0.015..0.060 | Upper clamp (~7.5% retrace) intentional — prevents loose trailing |
| `institutional_trailing.early_trigger` | `activation_pct × 0.85` | 0.020..0.06 | |
| `institutional_trailing.breakeven_trigger` | `activation_pct × 1.5` | 0.040..0.12 | |
| `institutional_trailing.activation_trigger` | `target_pct × 0.55` | 0.08..0.20 | |
| `institutional_trailing.trailing_distance` | `drawdown_pct × 1.1` | 0.030..0.12 | |
| `institutional_trailing.adaptive_drawdown` | `[td, td×0.9, td×0.75, td×0.6]` | each ≥ 0.020 | `td` = trailing_distance |
| `risk.profit_floor.lock_pct` | `avg_gain × 0.20 / 100` | 0.06..0.15 | |
| `risk.profit_floor.trail_pct` | `1.0 - (avg_retrace_abs × 0.8 / 100)` | 0.55..0.92 | |
| `risk.time_stop.trend.{symbol}` | session-aware (from existing `suggested_time_stop` logic) | 6..30 min | |

`institutional_trailing` is nested under the symbol key (`:nifty` or `:sensex`).

`early_sl_offset` is not derived from stats — it remains at its current configured value (insufficient data to derive a meaningful stop offset from historical candles alone).

---

## Job

### `WeeklyCalibrationJob`

```ruby
class WeeklyCalibrationJob < ApplicationJob
  queue_as :background

  def perform(symbol: nil, weeks: 52)
    symbols = symbol ? [symbol.upcase] : %w[NIFTY SENSEX]
    symbols.each do |sym|
      result = Options::AutoCalibrator.call(symbol: sym, weeks: weeks)
      if result
        CalibrationNotifier.notify(sym, result)
      else
        CalibrationNotifier.notify_error(sym, 'AutoCalibrator returned nil — all DhanHQ fetches failed')
      end
    rescue StandardError => e
      Rails.logger.error("[WeeklyCalibrationJob] #{sym} failed: #{e.class} — #{e.message}")
      CalibrationNotifier.notify_error(sym, e)
    end
  end
end
```

Processes symbols sequentially to respect DhanHQ rate limits. Each symbol is independently rescued — a NIFTY failure does not prevent SENSEX from running. `AutoCalibrator.call` is documented as non-raising and returns `nil` on total failure; the job checks for nil before calling `notify` vs `notify_error`.

### `config/recurring.yml` addition

```yaml
weekly_options_calibration:
  class: WeeklyCalibrationJob
  schedule: every Sunday at 6:00 am Asia/Kolkata
  queue_name: background
  priority: 3
  description: "Weekly ATM±1 options calibration — generates config patch proposal for NIFTY and SENSEX"
```

---

## Notifications

### `CalibrationNotifier`

Thin wrapper around `TelegramNotifier`. Sends two messages per symbol on success; one error message on failure.

**Message 1 — Summary:**
```
📊 SENSEX Weekly Calibration — 2026-03-22

CE ATM  MaxGain: +18.4%  Retrace: -14.2%  OC: +3.1%
CE OTM1 MaxGain: +24.1%  Retrace: -19.8%  OC: -1.2%
PE ATM  MaxGain: +16.9%  Retrace: -13.1%  OC: -0.4%

Score: 4.2 (balanced)  Confidence: high (n=52)
⚠️ REGIME SHIFT — avg_retrace_abs 14.2% → 31.8% (+1.8σ)
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

Only keys that differ from current config by >10% are shown. No patch message sent if nothing changed significantly (run recorded but no Telegram patch message).

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

**Auth:** No additional auth guard — matches the existing circuit breaker endpoint pattern (`POST /api/circuit_breaker/trip` is also unguarded). The API is assumed to be internal/local access only. Document this assumption explicitly in the controller.

**Idempotency:** Applying an already-applied run (`applied_at` is set) returns `422 Unprocessable Entity` with `{error: "already applied"}`. Double-apply is not allowed to prevent accidental config re-overwrites.

### Endpoints

| Method | Path | Action |
|--------|------|--------|
| `GET` | `/api/calibration_runs` | List recent runs (symbol filter, pending/applied filter) |
| `GET` | `/api/calibration_runs/:id` | Full patch + stats for one run |
| `POST` | `/api/calibration_runs/:id/apply` | Apply patch to settings, set `applied_at`; 422 if already applied |

---

## `CalibrationRun` Model Methods

### `propose_config!`

Pre-versioning: no-op. The `proposed_patch` is already stored in `calibration_runs.proposed_patch` and accessible via API — there is no need to also write it to the `settings` table. The method exists as a versioning hook only.

Post-versioning: creates an `AlgoConfigVersion` record so the proposal appears in the Settings UI and can be applied from there.

```ruby
def propose_config!
  return unless defined?(AlgoConfigVersion)

  AlgoConfigVersion.create!(
    name: "calibration-#{symbol.downcase}-#{created_at.strftime('%Y%m%d')}",
    overrides: proposed_patch,
    source: 'calibration',
    calibration_run_id: id
  )
end
```

### `apply!(applied_by: 'api')`

Deep-merges `proposed_patch` into `algo_config_overrides` in the `settings` table. Uses `Setting.put` (not `upsert`) to ensure the Solid Cache entry for `setting:algo_config_overrides` is busted immediately. Also calls `AlgoConfig.reset!` to bust the in-process 30-second config cache. Trading daemon sees the new config on its next `AlgoConfig.fetch` call.

**Merge safety:** `proposed_patch` contains only scalar `risk.*` and `institutional_trailing.*` keys (no config arrays). This means plain `Hash#deep_merge` is safe here — `AlgoConfig`'s custom `deep_merge_hashes_with_arrays` (which handles array-of-hashes merging keyed on `:key`) is not required because the patch builder never emits array-valued keys. If this constraint is ever relaxed, `apply!` must switch to `AlgoConfig.send(:deep_merge_hashes_with_arrays, current, proposed_patch)`.

**Key format:** Both `current` (parsed from `Setting.find_by`) and `proposed_patch` (retrieved from JSONB column) use **string keys**. `deep_merge` operates on matching string keys. `AlgoConfig.fetch` applies `deep_symbolize_keys` after reading — this is handled by `AlgoConfig`, not `apply!`.

```ruby
def apply!(applied_by: 'api')
  raise 'already applied' if applied_at.present?

  current = JSON.parse(Setting.find_by(key: 'algo_config_overrides')&.value || '{}')
  # proposed_patch from JSONB is already string-keyed; deep_merge is safe (no array-valued keys)
  merged  = current.deep_merge(proposed_patch.deep_stringify_keys)
  Setting.put('algo_config_overrides', merged.to_json)  # busts Solid Cache entry
  AlgoConfig.reset!                                       # busts in-process cache
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
| `app/services/options/auto_calibrator.rb` | Orchestrator (non-raising) |
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
| `spec/requests/api/calibration_runs_spec.rb` | Request spec: index, show, apply (success + 422) |

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
- **All fetches fail for a symbol:** `AutoCalibrator.call` returns `nil`. Job logs error, calls `CalibrationNotifier.notify_error`. No `CalibrationRun` record created.
- **Regime detector has insufficient history:** Returns `shift: false` silently, proceeds with full-window calibration.
- **Telegram send failure:** Log error, do not retry — the run record exists and is accessible via API.
- **Apply fails (settings write error):** `apply!` raises, controller returns 500. `applied_at` remains null — run stays in pending state.
- **Double apply:** `apply!` raises `'already applied'` early. Controller returns 422.

---

## Testing Strategy

- `ExpiryCalendar`: unit test Thursday/Friday logic, edge cases (run on expiry day itself, run mid-week), `ArgumentError` for unknown symbol
- `StrikeAggregator`: unit test weighted average with known inputs; verify OTM1/OTM2 labelling contract
- `RegimeDetector`: unit test with fixture `CalibrationRun` records; test below-threshold, above-threshold, and insufficient-history (< 12 records) cases
- `CalibrationConfigPatchBuilder`: unit test each formula with known stats; test clamp boundaries; test 10% change filter (no key emitted when change < 10%)
- `AutoCalibrator`: integration spec with stubbed DhanHQ and stubbed sub-services; test nil return on total fetch failure
- `WeeklyCalibrationJob`: test `perform` with `symbol:` arg; test nil symbol (both symbols run); test that SENSEX still runs when NIFTY block raises
- `CalibrationRun`: unit test `apply!` deep-merge and cache bust (`Setting.put` called, `AlgoConfig.reset!` called); test double-apply raises; test `propose_config!` no-op when `AlgoConfigVersion` undefined
- `Api::CalibrationRunsController`: request spec covering index, show, successful apply, double-apply 422

All DhanHQ calls stubbed in specs via WebMock — no live API calls in tests.

---

## Compatibility Notes

- **Pre-versioning:** `propose_config!` is a no-op. `apply!` uses `Setting.put` + `AlgoConfig.reset!`. Works today.
- **Post-versioning:** When `AlgoConfigVersion` is defined, `propose_config!` creates a version record. `apply!` routes through `AlgoConfigVersion#activate`. `CalibrationRun` gains a `config_version_id` FK in a follow-up migration. No controller or job changes.
- **Rake task:** Never modified by this feature. Continues to use `HistoricalCalibrationEngine` directly.
