# Regime-Adaptive Entry Bar — Design Spec

**Date:** 2026-03-18
**Status:** Draft
**Strategy:** ExpiryTrendV1 (long options, trend-following)

---

## Problem

The current strategy loses consistently across all configurations (profit factor 0.01–0.29, win rate 20–26%). Root cause: entry bar is fixed regardless of regime strength. The Router's session/day_type filtering reduces trade count but does not improve trade quality. `volume_spike_factor` is hardcoded at 1.15–1.2, which is so permissive it passes near-random noise.

---

## Goal

Make the entry bar **adaptive**: strong regime + IV expanding = lower spike threshold. Weak regime or contracting IV = higher bar or skip entirely. Remove session windows as gating mechanisms — regime strength becomes the primary filter.

---

## Architecture

### Flow per bar

```
RegimeScorer.score_at(index)       → regime_score (0–100)
IvExpansionSignal.modifier_at      → iv_modifier  (-15..+15)
htf_bias misaligned?               → -5 penalty (if htf_bias present and != structure direction)

effective_score = (regime_score + iv_modifier + htf_penalty).clamp(0.0, 100.0)

ExpiryTrendV1:
  1. skip if effective_score < REGIME_FLOOR (55)
  2. skip if structure not :bullish or :bearish
  3. skip if no pullback
  4. adaptive_spike_factor = SPIKE_CURVE step lookup (first row where effective_score >= threshold)
  5. skip if volume_ratio < adaptive_spike_factor
  6. enter trade
```

`effective_score` is assembled **inside `ExpiryTrendV1`** using context fields. `ContextBuilder` does not compute it.

---

## New Component: `IvExpansionSignal`

**File:** `lib/backtest_engine/market/iv_expansion_signal.rb`

Wraps the ATM call `IvSeries` object returned by `BacktestSession#build_iv_series`. Computes a rolling IV delta and returns a float modifier in [-15.0, +15.0].

```
rolling_avg = readings_before(timestamp, period).sum / period.to_f
modifier    = clamp(((current_iv - rolling_avg) / rolling_avg) * 100, -15.0, 15.0)

Returns 0.0 if:
  - current_iv is nil
  - readings_before returns fewer than period values
  - rolling_avg is zero
```

**Parameters:**
- `period` (default: 10) — number of bars for the rolling average. Exposed as `iv_expansion_period` in `DEFAULT_INDICATOR_PARAMS`.

**Wiring:** instantiated in `BacktestSession#run` after `build_iv_series`, stored as `@iv_expansion_signal`. `modifier_at(timestamp)` is called in `build_indicators` (passed as the keyword argument `iv_expansion_signal:`), and the result is stored as `iv_expansion` in the indicators hash.

---

## New Method on `IvSeries`: `readings_before`

`readings_before(timestamp, n) → Array<Float>`

- Returns the last `n` IV float values (not hashes) for candles whose timestamp is strictly less than the given `timestamp`
- Timestamp comparison uses the same dual-type handling as `iv_for`: match both `t == timestamp` and `t == timestamp.to_i`
- Returns an empty array if fewer than `n` qualifying readings exist

---

## New Method on `CandleSeries`: `volume_ratio`

`volume_ratio(index, period:) → Float`

```ruby
def volume_ratio(index, period:)
  return 1.0 if index < period
  window = candles[(index - period)...index]
  return 1.0 if volume_unavailable?(window)
  average = window.sum(&:volume) / period.to_f
  return 1.0 if average.zero?
  candles[index].volume.to_f / average
end
```

Returns `1.0` (neutral — does not spike) when volume data is unavailable, window not yet full, or average is zero. The `period` used is `indicator_params[:volume_spike_period]`.

---

## Changes to `ContextBuilder`

| Field | Change | Type | Description |
|---|---|---|---|
| `iv_expansion` | Added | Float (-15..+15) | Raw IV expansion modifier |
| `volume_ratio` | Added | Float | `current_volume / rolling_avg_volume` over `volume_spike_period` bars |
| `volume_spike` | **Removed** | — | No other strategy or analytics consumer reads this field |

`volume_spike_factor` **removed** from `DEFAULT_INDICATOR_PARAMS`.
`iv_expansion_period: 10` **added** to `DEFAULT_INDICATOR_PARAMS`.

---

## Changes to `BacktestSession`

- `day_type:` keyword **retained** in `run` signature with default `:normal`. It is no longer used for routing but continues to flow into `record_decision` and `open_position_from_signal` for analytics tagging. This avoids a breaking change in callers.
- `session_for` retained for analytics tagging only — not used for routing
- `Metrics::Trade` retains `day_type` field
- `BatchRunner` removes `day_type` from per-day hash (it was only there to feed the router)
- `IvExpansionSignal` instantiated in `run` after `build_iv_series`, receives same `IvSeries` object
- `build_indicators` private method: adds `iv_expansion_signal:` keyword argument; passes `iv_expansion` (from `iv_expansion_signal.modifier_at(timestamp)`) and `volume_ratio` (from `indicator_series.volume_ratio(candle_index, period: indicator_params[:volume_spike_period])`); removes `volume_spike`
- `regime_scorer:` default **remains `false`** — `ExpiryTrendV1` handles nil `regime_score` gracefully
- Router `tradable?` call updated to pass only `regime:`
- `volume_spike_factor` removed from `DEFAULT_INDICATOR_PARAMS`; `iv_expansion_period: 10` added

---

## Changes to `ExpiryTrendV1`

### Removed
- `valid_time?` and `ENTRY_WINDOW` constant
- `htf_bias_allows?` as hard gate — replaced by soft score penalty
- `volume_spike?` boolean condition
- `iv < 60` guard in `tradable_structure?` — the IV expansion signal now handles this continuously via the effective_score modifier; a hard IV ceiling is no longer needed

### Constants unchanged
`SL_PCT`, `TARGET_PCT`, `TRAIL_TRIGGER`, `MAX_HOLD_MINUTES`

### New constants

```ruby
REGIME_FLOOR = 55

# Step function lookup: iterate rows in order (highest threshold first).
# Return the factor for the FIRST row where effective_score >= threshold (>=, not >).
# A score of exactly 80 matches [80, 1.05]. A score of 70 matches [70, 1.2].
# Score is guaranteed >= REGIME_FLOOR (55) when called, so a row always matches.
SPIKE_CURVE = [
  [80, 1.05],
  [70, 1.2],
  [60, 1.4],
  [55, 1.8],
].freeze
```

### `effective_score` and helpers

```ruby
def effective_score
  base    = context[:regime_score].to_f   # 0.0 if nil
  iv_mod  = context[:iv_expansion].to_f   # 0.0 if nil
  htf_pen = htf_misaligned? ? -5.0 : 0.0
  (base + iv_mod + htf_pen).clamp(0.0, 100.0)
end

def htf_misaligned?
  htf = context[:htf_bias]
  return false if htf.nil?
  htf != context[:structure]   # :bullish/:bearish/:range direct comparison
end

def adaptive_spike_factor
  score = effective_score
  SPIKE_CURVE.each { |threshold, factor| return factor if score >= threshold }
  Float::INFINITY   # unreachable when called after regime_strong_enough? guard
end
```

**Nil-safety:** if `regime_score` is nil, `effective_score` ≈ 0.0, which is below `REGIME_FLOOR` — all entries skip with reason "Weak regime". No crash.

### Call order

```ruby
def call
  return no_trade!("Weak regime")  unless regime_strong_enough?
  return no_trade!("No structure") unless tradable_structure?
  return no_trade!("No pullback")  unless pullback?

  if bullish_setup?
    build_trade(:call)
  elsif bearish_setup?
    build_trade(:put)
  else
    no_trade!("No setup")
  end
end
```

`bullish_setup?` and `bearish_setup?` check `context[:volume_ratio] >= adaptive_spike_factor` in place of the old `context[:volume_spike]` boolean.

---

## Changes to `Router`

```ruby
def tradable?(regime:, **)
  %i[trend_bull trend_bear].include?(regime.to_sym)
end

def strategy_for(regime:, **)
  return nil unless tradable?(regime: regime)
  ExpiryTrendV1
end
```

The `**` splat absorbs any extra keywords silently. The `BacktestSession` call site is updated to pass only `regime:`.

---

## Optimisable Parameters

| Parameter | Default | Range to explore |
|---|---|---|
| `regime_floor` | 55 | 45–70 |
| `iv_expansion_period` | 10 | 5–20 |
| `pullback_ema_period` | 20 | 10–30 |

---

## Files

### Create
| File | Purpose |
|---|---|
| `lib/backtest_engine/market/iv_expansion_signal.rb` | New component |
| `spec/market/iv_expansion_signal_spec.rb` | New specs |

### Modify
| File | Change summary |
|---|---|
| `lib/backtest_engine/market/iv_series.rb` | Add `readings_before(timestamp, n)` |
| `lib/backtest_engine/market/candle_series.rb` | Add `volume_ratio(index, period:)` |
| `lib/backtest_engine/market/context_builder.rb` | Add `iv_expansion`, `volume_ratio`; remove `volume_spike` |
| `lib/backtest_engine/strategies/expiry_trend_v1.rb` | Adaptive entry logic; remove time window and IV ceiling |
| `lib/backtest_engine/strategies/router.rb` | Remove session/day_type from both methods |
| `lib/backtest_engine/backtest_session.rb` | Wire IvExpansionSignal; update DEFAULT_INDICATOR_PARAMS; update router call |
| `scripts/jan_2025_expiry_trend_v1.rb` | Remove `volume_spike_factor`; add `iv_expansion_period` to `indicator_params`; update `param_grid` to sweep `regime_floor`/`iv_expansion_period` |
| `spec/strategies/expiry_trend_v1_spec.rb` | Rewrite for new call chain; add effective_score / adaptive threshold cases |
| `spec/strategies/router_spec.rb` | Remove session-based filtering tests; replace with regime-only tests (pass only `regime:` keyword) |
| `spec/backtest_session_spec.rb` | Remove `day_type:` from `run` calls that no longer need it; update router mock if present |
| `spec/batch_runner_spec.rb` | Remove `day_type` from per-day hash; remove/replace "passes day_type per day" test |
| `spec/market/candle_series_spec.rb` | Add specs for `volume_ratio` |

---

## Test Outline: `iv_expansion_signal_spec.rb`

- Returns `0.0` with no readings in IvSeries
- Returns `0.0` when fewer than `period` readings exist before the given timestamp
- Returns positive float when current IV > rolling average
- Returns negative float when current IV < rolling average
- Clamps at `+15.0` on extreme positive expansion
- Clamps at `-15.0` on extreme negative expansion
- Handles mixed integer/Time timestamp types (mirrors `IvSeries#iv_for`)
- Returns `0.0` when rolling average is zero
