# Underlying-Context-Aware Trailing Exit

**Date:** 2026-03-25
**Branch:** feature/regime-aware-risk-engine
**Status:** Approved — pending implementation

---

## Problem

The trailing stop in `UnifiedExitChecker` is purely option-premium based. It waits for a fixed
percentage drop from HWM (e.g. 4.23% for a SENSEX position at 141% profit) with no knowledge of
whether the underlying index has already reversed. SENSEX options can retrace ~99.8% post-peak;
by the time the premium drops 4%, significant profit may have evaporated.

`UnderlyingExitRule` (which reads BOS, trend score, ATR) exists but runs only in the interval
enforcement cycle — which is skipped in live tick-first mode. It is effectively dormant for
real-time exits.

---

## Goal

Wire `UnderlyingMonitor` signals into the tick-first trailing path so that:

1. A confirmed BOS break against the position triggers an **immediate exit** regardless of HWM drop.
2. Trend weakness or ATR collapse **tightens the trailing buffer** (compresses `allowed_dd`) so
   the trailing fires sooner on any pullback.

Activation: only when trailing is already armed (position profitable enough). `EarlyTrendFailure`
already covers the pre-trailing window.

---

## Architecture

```
check_exit_conditions(tracker)
  ...
  [3.5] percentage_pnl_exit_hit?          ← suppressed when trailing armed
  [4]   premium_momentum_failure_hit?
  [5]   trailing section (replaces the single trailing_stop_hit? call):
          underlying_ctx = evaluate_underlying_context(tracker, snapshot)
          if underlying_ctx[:action] == :exit
            → return UNDERLYING_STRUCTURE_BREAK / UNDERLYING_DUAL_WEAKNESS
          end
          # The original trailing_stop_hit?(tracker, snapshot) call is replaced by:
          trailing_stop_hit?(tracker, snapshot, tightening_multiplier: underlying_ctx[:multiplier])
            → adaptive_trailing_exit?(..., tightening_multiplier:)
                effective_allowed_dd = allowed_dd * tightening_multiplier
  [6]   check_structure_invalidation
  ...
```

`evaluate_underlying_context` only runs when `trailing_armed?` returns true.
The original `trailing_stop_hit?(tracker, snapshot)` call site is **replaced** — not supplemented.

---

## Signal → Action Mapping

| Underlying signal | Action | Multiplier | Log reason |
|---|---|---|---|
| BOS broken against position direction | `:exit` | — | `UNDERLYING_STRUCTURE_BREAK` |
| Weak trend **AND** ATR collapsing | `:exit` | — | `UNDERLYING_DUAL_WEAKNESS` |
| Weak trend **OR** ATR collapsing | `:tighten` | `0.5` | `UNDERLYING_WEAKENING` |
| All clear / data unavailable | `:hold` | `1.0` | — |

When not armed, returns `{ action: :hold, multiplier: 1.0, reason: nil }` immediately — the
`multiplier: 1.0` default ensures `trailing_stop_hit?` behaves identically to today.

**`smc_bias_flip` explicitly excluded:** That signal is lower-confidence and already covered by
`UnderlyingExitRule` in the interval enforcement cycle. Including it here would add latency
(60s BIAS_TTL cache) for minimal additional signal value.

**Tightening effect at 141% profit (SENSEX example):**
- Normal: `allowed_dd = 0.06`, trigger at 4.23% HWM drop → LTP ~641 from 669
- Tightened (0.5×): `effective_allowed_dd = 0.03`, trigger at 2.1% HWM drop → LTP ~655 from 669

---

## Components

### New: `app/services/live/underlying_context_evaluator.rb`

Plain `module` (not `module_function`) included inside `class << self` in `UnifiedExitChecker`.
`evaluate_underlying_context` receives `tracker` and `snapshot` as parameters. `exit_config` is a
zero-argument cache method on the same singleton. The evaluator therefore calls
`trailing_armed?(tracker, snapshot, exit_config)` with all three required arguments obtainable
without adding new parameters to the public interface.

Public interface:

```ruby
evaluate_underlying_context(tracker, snapshot)
# → { action: :exit | :tighten | :hold, multiplier: Float, reason: String | nil }
```

#### `build_underlying_position_data(tracker)`

Reads from `Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)` (the same source
`trailing_stop_hit?` already uses for `pos_data`). This carries `underlying_segment`,
`underlying_security_id`, and `position_direction` already populated by
`Positions::MetadataResolver`. Falls back to `tracker.meta` for `index_key`.

Returns an OpenStruct with exactly the fields `UnderlyingMonitor` needs:

```ruby
OpenStruct.new(
  tracker_id:             tracker.id,
  index_key:              tracker.meta&.dig('index_key'),
  underlying_symbol:      tracker.meta&.dig('index_key'),   # fallback in determine_index_cfg
  underlying_segment:     pos_data&.underlying_segment,
  underlying_security_id: pos_data&.underlying_security_id,
  position_direction:     normalized_position_direction(tracker, pos_data),
  underlying_ltp:         nil  # UnderlyingMonitor will fetch from TickQuery
)
```

#### `normalized_position_direction(tracker, pos_data)`

Maps raw direction values to `:bullish` / `:bearish` for `UnderlyingMonitor.structure_state`
which only handles those two symbols:

```
long_ce, bullish, call  → :bullish
long_pe, bearish, put   → :bearish
nil / unknown           → :bullish  (safe default — false negative, not false positive)
```

Source priority: `pos_data.position_direction` → `tracker.meta['direction']` → `:bullish`

#### Private signal helpers

```ruby
bos_broken_against?(state, direction)
# state.bos_state == :broken &&
# (direction == :bullish && state.bos_direction == :bearish) ||
# (direction == :bearish && state.bos_direction == :bullish)

trend_weak?(state)
# state.trend_score && state.trend_score.to_f < cfg[:trend_score_threshold] (default 15)

atr_collapsing?(state)
# state.atr_trend == :falling &&
# state.atr_ratio && state.atr_ratio.to_f < cfg[:atr_ratio_threshold] (default 0.65)
```

#### Config

```yaml
# config/algo.yml under risk:
underlying_context_exit:
  enabled: true
  trend_score_threshold: 15     # trend_score below this = weak
  atr_ratio_threshold: 0.65     # atr_ratio below this (and falling) = collapsing
  tightening_multiplier: 0.5    # applied to allowed_dd when :tighten
```

**Relationship with `feature_flags.enable_underlying_aware_exits`:**
That flag gates `UnderlyingExitRule` in the interval enforcement cycle only. The new
`underlying_context_exit.enabled` flag gates this module in the tick-first path. When both are
`true`, both paths are active — `UnderlyingExitRule` as interval fallback, this module as
real-time. They are complementary, not redundant.

---

### Modified: `app/services/live/unified_exit_checker.rb`

Four targeted edits:

**1.** Add `include Live::UnderlyingContextEvaluator` inside `class << self`.

**2.** In `check_exit_conditions`, replace the single existing `trailing_stop_hit?` call with:

```ruby
underlying_ctx = evaluate_underlying_context(tracker, snapshot)
if underlying_ctx[:action] == :exit
  return {
    exit: true,
    reason: underlying_ctx[:reason],
    path: 'underlying_context_exit',
    pnl_pct: (pnl_pct * 100.0).round(2)
  }
end

if trailing_stop_hit?(tracker, snapshot, tightening_multiplier: underlying_ctx[:multiplier])
  return { exit: true, reason: 'TRAILING_STOP', path: 'trailing_stop',
           pnl_pct: (pnl_pct * 100.0).round(2) }
end
```

**3.** `trailing_stop_hit?` — add `tightening_multiplier: 1.0` kwarg. Pass it to
`adaptive_trailing_exit?` only. The `Orders::Analyzer` gamma/MFE path (which handles
NIFTY/BANKNIFTY/SENSEX when no adaptive tiers match) is **not** modified. The legacy trailing
fallback (non-index instruments, path 3 in the method) is also **not** modified — those
instruments lack institutional trailing calibration and the tightening concept doesn't apply.

**4.** `adaptive_trailing_exit?` — add `tightening_multiplier: 1.0` kwarg:

```ruby
effective_allowed_dd = allowed_dd * tightening_multiplier
drop_from_peak_pct = (hwm - pnl_value) / hwm * peak_profit_pct
return false unless drop_from_peak_pct >= effective_allowed_dd
```

---

## Files

| Action | Path |
|---|---|
| NEW | `app/services/live/underlying_context_evaluator.rb` |
| MODIFY | `app/services/live/unified_exit_checker.rb` |
| NEW | `spec/services/live/underlying_context_evaluator_spec.rb` |
| MODIFY | `spec/services/live/unified_exit_checker_spec.rb` |
| MODIFY | `config/algo.yml` |

---

## Error Handling

| Failure | Behaviour |
|---|---|
| `UnderlyingMonitor` raises / returns default state | `:hold, multiplier: 1.0` — trailing unchanged |
| `ActiveCache` returns nil for `pos_data` | `build_underlying_position_data` returns OpenStruct with nil segment/sid; `UnderlyingMonitor.determine_index_cfg` falls through to `MetadataResolver`; on failure returns default state → `:hold` |
| `position_direction` unknown | Normalised to `:bullish`; unknown direction never matches bearish BOS — false negative only, never false positive |
| `tightening_multiplier` on `Orders::Analyzer` path | Explicitly excluded — gamma/MFE math not touched |
| Tightening multiplier on legacy trailing path | Explicitly excluded — non-index instruments use fixed `drop_threshold`, tightening concept inapplicable |
| Rapid BOS wick flip | `UnderlyingMonitor` checks candle closes vs swing extremes — single-wick noise filtered |
| Dual tick race | `ExitEngine` Redis lock per tracker prevents duplicate exits |

---

## Test Plan

### `spec/services/live/underlying_context_evaluator_spec.rb`

- Returns `{ action: :hold, multiplier: 1.0 }` when trailing not armed
- Returns `{ action: :hold, multiplier: 1.0 }` when `UnderlyingMonitor` returns default state
- Returns `{ action: :hold, multiplier: 1.0 }` when `underlying_context_exit.enabled: false`
- Returns `:exit` + `UNDERLYING_STRUCTURE_BREAK` on BOS break against long_ce (bullish) position
- Returns `:exit` + `UNDERLYING_STRUCTURE_BREAK` on BOS break against long_pe (bearish) position
- Returns `:exit` + `UNDERLYING_DUAL_WEAKNESS` when trend weak AND ATR collapsing
- Returns `:tighten` (multiplier 0.5) when trend weak only
- Returns `:tighten` (multiplier 0.5) when ATR collapsing only
- Returns `{ action: :hold, multiplier: 1.0 }` when underlying is healthy
- Respects configurable `trend_score_threshold` and `atr_ratio_threshold`
- `smc_bias_flip: true` alone does not trigger exit or tighten
- `multiplier` is always `Float`, never `nil`, in all return paths

### `spec/services/live/unified_exit_checker_spec.rb` additions

- At 141% profit with BOS break → exits with `UNDERLYING_STRUCTURE_BREAK`, path `underlying_context_exit`
- At 141% profit with trend weak → `adaptive_trailing_exit?` uses halved `allowed_dd` (2.1% trigger vs 4.23%)
- At 141% profit with healthy underlying → trailing fires at normal 4.23% HWM drop
- `evaluate_underlying_context` not called when trailing not armed
- Original `trailing_stop_hit?` call site is replaced (no duplicate calls)
