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
EXPIRY_WEEKDAY = { 'NIFTY' => 4, 'SENSEX' => 5 }.freeze  # Thu=4, Fri=5 — uses Date#wday (Sunday=0 convention, NOT Date#cwday)
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

**Unit convention for all input stat keys:** All `avg_*` and `oc_stddev` values are **percentage points** (e.g., `14.2` for 14.2%), not decimal fractions. This matches how `HistoricalCalibrationEngine` stores them (sourced directly from CSV percentage columns). The `/100` terms throughout the formula table are intentional — they convert percentage-point stats into the project's decimal config format (`0.12` = 12%).

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
| `risk.profit_floor.lock_pct` | `avg_gain × 0.20 / 100` | 0.06..0.15 | |
| `risk.profit_floor.trail_pct` | `1.0 - (avg_retrace_abs × 0.8 / 100)` | 0.55..0.92 | |
| `risk.time_stop.trend.{symbol}` | session-aware (from existing `suggested_time_stop` logic) | 6..30 min | |

`institutional_trailing` is nested under the symbol key (`:nifty` or `:sensex`).

`early_sl_offset` is not derived from stats — it remains at its current configured value (insufficient data to derive a meaningful stop offset from historical candles alone).

`adaptive_drawdown` is **excluded** from auto-derived keys. It is an array-of-hashes config key (`[{min_profit:, drawdown:}, ...]`) with `min_profit:` tier levels that are not derivable from historical candle stats. Including it would require `AlgoConfig.send(:deep_merge_hashes_with_arrays, ...)` and full tier reconstruction. Instead, `CalibrationConfigPatchBuilder` leaves `adaptive_drawdown` untouched — the trader adjusts it manually using `trailing_distance` as a reference point. **This is the only array-valued key in `institutional_trailing`; all other emitted keys are scalars, keeping `apply!`'s use of plain `Hash#deep_merge` safe.**

---

## Job

### `WeeklyCalibrationJob`

```ruby
class WeeklyCalibrationJob < ApplicationJob
  queue_as :background

  # Use positional defaults (not keyword args) — Active Job serializes
  # keyword arguments as a single positional hash, which causes ArgumentError
  # with keyword-only signatures in Ruby 3.3. Positional defaults work
  # correctly for both scheduler (no args) and manual enqueue.
  def perform(symbol = nil, weeks = 52)
    symbols = symbol ? [symbol.to_s.upcase] : %w[NIFTY SENSEX]
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

Processes symbols sequentially to respect DhanHQ rate limits. Each symbol is independently rescued — a NIFTY failure does not prevent SENSEX from running. Enqueue with `WeeklyCalibrationJob.perform_later('NIFTY')` (positional) not `perform_later(symbol: 'NIFTY')` (keyword).

### `config/recurring.yml` addition

Add under the **`production:`** environment key only (matching all other production-only jobs in `config/recurring.yml`). Do not add under `development:` — calibration should not run automatically on developer machines.

```yaml
production:
  # ... existing entries ...
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
| `POST` | `/api/analysis/:index_key/ai_snapshot` | On-demand Ollama AI analysis for current market context |

---

## Dashboard UI

### Settings view — `CalibrationRunsPanel.vue` (new)

New section added at the bottom of `Settings.vue`, below the existing config tree editor. Displays the last 5 `CalibrationRun` records per symbol, ordered newest first.

**Layout per run:**
```
┌─────────────────────────────────────────────────────────┐
│ SENSEX  2026-03-23  Score: 4.2  Confidence: high        │
│ ⚠️ REGIME SHIFT — avg_retrace_abs jumped +1.8σ          │
│                                                          │
│ trailing.activation_pct:    0.025 → 0.030               │
│ institutional_trailing.sensex.breakeven_trigger: ...     │
│                                                          │
│ [  APPLY  ]   52 weeks · ATM±1                          │
└─────────────────────────────────────────────────────────┘
```

- **Pending runs**: highlighted border (cyan), Apply button active
- **Applied runs**: greyed out, shows `Applied ${date} via ${applied_by}` instead of Apply button
- **Regime shift runs**: amber warning badge
- Patch diff shows only changed keys (same logic as Telegram message — keys differing >10% from current config)

**Data fetching:** On mount, calls `GET /api/calibration_runs?limit=10` (last 5 per symbol = max 10). Re-fetches after successful apply. No polling — calibration runs are low-frequency.

**Apply flow:**
1. Click Apply → confirm dialog: "Apply SENSEX calibration from 2026-03-23? This will update your live trading config."
2. On confirm → `POST /api/calibration_runs/:id/apply`
3. On success → show "✅ Config updated — daemon picks up in ~30s", mark run as applied inline
4. On 422 → show "Already applied"
5. On 500 → show error message

**New files:**
- `dashboard/src/components/settings/CalibrationRunsPanel.vue`

**Modified files:**
- `dashboard/src/views/Settings.vue` — import and render `<CalibrationRunsPanel />` below the config tree

---

### Analysis view — On-demand AI snapshot

**Backend: `POST /api/analysis/:index_key/ai_snapshot`**

New action on `AnalysisController`. Gathers current market context and calls Ollama synchronously. Returns within `OLLAMA_TIMEOUT` (default 120s).

```ruby
def ai_snapshot
  index_key = params[:index_key].to_s.upcase
  instrument = find_instrument(index_key)
  return render json: { error: 'Index not found' }, status: :not_found unless instrument

  stored = AnalysisStore.read_all(index_key)
  latest_run = CalibrationRun.where(symbol: index_key).order(created_at: :desc).first
  ltp = Live::TickCache.ltp(instrument.exchange_segment, instrument.security_id)

  prompt = AiSnapshotPromptBuilder.build(
    index_key: index_key,
    ltp: ltp,
    smc: stored[:smc]&.dig(:data),
    regime: stored[:regime]&.dig(:data),
    calibration_stats: latest_run&.raw_stats
  )

  client = Services::Ai::OpenaiClient.instance
  return render json: { error: 'AI not configured' }, status: :service_unavailable unless client.enabled?

  response = client.chat(
    messages: [
      { role: 'system', content: 'You are an expert intraday options trader for Indian index markets. Be concise and data-driven.' },
      { role: 'user', content: prompt }
    ],
    temperature: 0.3
  )

  render json: { analysis: response, generated_at: Time.current.iso8601 }
rescue StandardError => e
  Rails.logger.error("[AnalysisController] ai_snapshot error: #{e.class} - #{e.message}")
  render json: { error: e.message }, status: :internal_server_error
end
```

**`AiSnapshotPromptBuilder`** (new service, `app/services/ai_snapshot_prompt_builder.rb`):

Assembles a compact prompt from available data:
- Current LTP and index
- SMC structure (order blocks, BOS, trend direction) if available
- Market regime (trending/choppy/news-driven) if available
- Calibration stats from latest run (avg gain, retrace, session breakdown) if available
- Asks for: current bias, key levels to watch, entry timing, risk note

Falls back gracefully when any component is nil — the prompt is still valid with partial data.

**Dashboard: `AiInsights.vue` (modified)**

Adds a **"🤖 Snapshot"** button. On click:
1. Sets `snapshotLoading = true`, displays spinner overlay on the AI panel
2. Calls `POST /api/analysis/${currentIndex}/ai_snapshot`
3. On success: replaces displayed analysis with snapshot response + shows "🔴 Live snapshot · ${time}" badge instead of the scheduled analysis age
4. On error: shows inline error, keeps previous analysis visible
5. `snapshotLoading = false`

The snapshot result is **display-only** — it does not overwrite `AnalysisStore`. When the page is refreshed or the 30s poll fires, the display reverts to the latest scheduled analysis from `AnalysisStore`.

**`useAnalysis.js` (modified)**

Adds `fetchAiSnapshot()` function:
```js
async function fetchAiSnapshot() {
  try {
    snapshotLoading.value = true
    snapshotError.value = null
    const res = await fetch(`/api/analysis/${currentIndex.value}/ai_snapshot`, { method: 'POST' })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const data = await res.json()
    snapshotData.value = data
  } catch (e) {
    snapshotError.value = e.message
  } finally {
    snapshotLoading.value = false
  }
}
```

**New files:**
- `app/services/ai_snapshot_prompt_builder.rb`
- `spec/services/ai_snapshot_prompt_builder_spec.rb`

**Modified files:**
- `app/controllers/api/analysis_controller.rb` — add `ai_snapshot` action + route
- `config/routes.rb` — add `post :ai_snapshot` to analysis resource
- `dashboard/src/composables/useAnalysis.js` — add `snapshotLoading`, `snapshotData`, `snapshotError`, `fetchAiSnapshot`
- `dashboard/src/components/analysis/AiInsights.vue` — add Snapshot button + snapshot display state
- `dashboard/src/views/Analysis.vue` — pass `fetchAiSnapshot` + snapshot state to `AiInsights`

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
| `app/services/ai/ai_snapshot_prompt_builder.rb` | Assembles Ollama prompt from LTP, SMC, regime, calibration stats |
| `dashboard/src/components/settings/CalibrationRunsPanel.vue` | Settings panel: list pending/applied runs, Apply button |
| `spec/requests/api/analysis_ai_snapshot_spec.rb` | Request spec: success, 503 on AI error |
| `spec/services/ai/ai_snapshot_prompt_builder_spec.rb` | Unit spec: all context sources nil-safe |

### Modified files

| Path | Change |
|------|--------|
| `config/recurring.yml` | Add `weekly_options_calibration` schedule |
| `config/routes.rb` | Add `calibration_runs` resource + `ai_snapshot` route |
| `app/controllers/api/analysis_controller.rb` | Add `ai_snapshot` action |
| `dashboard/src/views/Settings.vue` | Render `CalibrationRunsPanel` per symbol |
| `dashboard/src/components/analysis/AiInsights.vue` | Add Snapshot button, loading/error states |
| `dashboard/src/composables/useAnalysis.js` | Add snapshot state and `fetchAiSnapshot` |

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

---

## UI Changes

### Settings View — Calibration Runs Panel

**New component:** `dashboard/src/components/settings/CalibrationRunsPanel.vue`

**Added to:** `dashboard/src/views/Settings.vue` as a new section below the existing settings form, rendered once for each watched symbol (`['NIFTY', 'SENSEX']`).

**Behaviour:**

- On mount, fetches `GET /api/calibration_runs?limit=10` (all symbols). Filters client-side by symbol to populate each panel.
- Displays the last 5 `CalibrationRun` records per symbol in reverse-chronological order.
- **Pending run** (no `applied_at`):
  - Cyan left border (`border-l-4 border-cyan-500`).
  - Active **Apply** button. Clicking opens a `window.confirm` dialog: `"Apply calibration patch for ${symbol}? This will update live config."`. On confirmation, calls `POST /api/calibration_runs/:id/apply`.
  - On success: applied run moves to greyed state; success toast shown.
  - On 422: toast shows `"Already applied"`.
  - On 500: toast shows `"Apply failed — check server logs"`.
- **Applied run** (has `applied_at`):
  - Greyed out, Apply button disabled. Shows applied timestamp (`applied_at` formatted as `dd MMM HH:mm`).
- **Regime shift run** (`regime_shift: true`):
  - Amber warning badge: `"⚠ Regime shift detected"` overlaid on the run card.
- **Patch diff:** Shows only config keys where the proposed value differs from current by ≥10%. Displayed as a compact key→value list (current → proposed). Keys derived from `proposed_patch` object; current values fetched from the same `GET /api/calibration_runs` response (include `current_snapshot` field in index response, see API section below).

**API addition for index response:** `GET /api/calibration_runs` returns each record with a `current_snapshot` field containing the currently-active values for each key in `proposed_patch`. This allows the frontend to compute diff without a separate request.

**Files to create/modify:**

| Path | Change |
|------|--------|
| `dashboard/src/components/settings/CalibrationRunsPanel.vue` | New component |
| `dashboard/src/views/Settings.vue` | Import and render `CalibrationRunsPanel` per symbol |

---

### Analysis View — On-Demand AI Snapshot

**Purpose:** Allow the user to trigger an immediate Ollama AI analysis from the Analysis view, without waiting for the next scheduled `AiTechnicalAnalysisJob` run. The snapshot uses local Ollama (same client used by existing AI analysis) and assembles a richer prompt including current regime and calibration context.

#### Backend

**New endpoint:** `POST /api/analysis/:index_key/ai_snapshot`

- Added to `app/controllers/api/analysis_controller.rb` as the `ai_snapshot` action.
- Route: `post 'analysis/:index_key/ai_snapshot', to: 'api/analysis#ai_snapshot'` in `config/routes.rb`.
- Calls `Services::Ai::AiSnapshotPromptBuilder.call(index_key:)` to assemble context.
- Passes assembled prompt to `Services::Ai::OpenaiClient.instance.chat(prompt)` (existing singleton — same client used by rake task).
- Returns `{ snapshot: "<markdown string>", generated_at: "<ISO8601>" }`.
- Does **not** write to `AnalysisStore` — snapshot is display-only and transient.
- On Ollama/OpenAI error: returns 503 `{ error: "AI service unavailable" }`.
- Timeout: 30 seconds (OpenAI client default). If exceeded, returns 504.

**New service:** `app/services/ai/ai_snapshot_prompt_builder.rb`

Assembles prompt from:
1. Current LTP — from `TickQuery.ltp(index_key)` (nil-safe: omits if unavailable).
2. Latest SMC analysis — from `AnalysisStore.read(index_key, :smc)` (nil-safe).
3. Current regime — from `AnalysisStore.read(index_key, :regime)` (nil-safe).
4. Latest calibration stats — from `CalibrationRun.where(symbol: index_key.upcase).order(created_at: :desc).first` (nil-safe).
5. Session context — from `TradingSession::Service.current_session_label` (nil-safe).

Returns a single prompt string. If all context sources return nil, returns a minimal prompt: `"Provide a brief technical outlook for #{index_key} options trading."`.

**Files to create/modify:**

| Path | Change |
|------|--------|
| `app/controllers/api/analysis_controller.rb` | Add `ai_snapshot` action |
| `app/services/ai/ai_snapshot_prompt_builder.rb` | New service |
| `config/routes.rb` | Add `ai_snapshot` route |
| `spec/requests/api/analysis_ai_snapshot_spec.rb` | Request spec: success, 503 on AI error |
| `spec/services/ai/ai_snapshot_prompt_builder_spec.rb` | Unit spec: all context sources nil-safe |

#### Frontend

**Modified:** `dashboard/src/components/analysis/AiInsights.vue`

- Accepts new prop: `snapshotData` (string or null), `snapshotLoading` (bool), `snapshotError` (string or null), `onSnapshot` (function).
- **Snapshot button:** `"🤖 Snapshot"` button in the component header. Disabled when `snapshotLoading` is true. Shows spinner overlay on the analysis text area while loading.
- On click, calls `onSnapshot()` (provided by `useAnalysis` composable via parent).
- When `snapshotData` is non-null, renders it **instead of** the polled `analysis` prop — snapshot takes display priority.
- When `snapshotError` is non-null, shows inline error message below the button.
- Snapshot display reverts to polled data on next `fetchLive()` call (i.e., when user switches symbol or triggers manual refresh). There is no explicit "clear snapshot" button.

**Modified:** `dashboard/src/composables/useAnalysis.js`

New reactive state added:
```js
const snapshotLoading = ref(false)
const snapshotData    = ref(null)
const snapshotError   = ref(null)
```

New function:
```js
async function fetchAiSnapshot() {
  snapshotLoading.value = true
  snapshotError.value   = null
  try {
    const res = await api.post(`/analysis/${activeIndex.value}/ai_snapshot`)
    snapshotData.value = res.data.snapshot
  } catch (err) {
    snapshotError.value = err.response?.data?.error || 'Snapshot failed'
  } finally {
    snapshotLoading.value = false
  }
}
```

`snapshotData` is reset to `null` inside `fetchLive()` so stale snapshot doesn't persist across symbol changes.

**Files to modify:**

| Path | Change |
|------|--------|
| `dashboard/src/components/analysis/AiInsights.vue` | Add Snapshot button, snapshot display, loading/error states |
| `dashboard/src/composables/useAnalysis.js` | Add `snapshotLoading`, `snapshotData`, `snapshotError`, `fetchAiSnapshot` |
