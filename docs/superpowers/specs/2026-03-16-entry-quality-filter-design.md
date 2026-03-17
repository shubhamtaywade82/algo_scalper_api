# Entry Quality Filter for Supertrend + ADX Strategy

**Date:** 2026-03-16
**Approach:** New `Signal::EntryQualityFilter` — hybrid hard gates + scoring system
**Branch:** `fix/logging-and-job-run-improvements`

## Context

The Supertrend + ADX entry strategy on the 1m timeframe currently has very loose entry criteria: any Supertrend flip with ADX ≥ 15 triggers a trade. This produces:

- **Overtrading** — entries in choppy/ranging markets where Supertrend flips frequently
- **Bad timing** — entering on weak flips (doji candles, barely crossing Supertrend level) that immediately reverse
- **Wrong direction** — signals fire at the tail end of moves when ADX is barely above 15

The existing `EntryFilterEngine` (BOS, range expansion, ATR rising checks) is skipped entirely in exit_testing mode and is a simple pass/fail gate in normal mode. There's no quality scoring or granular filtering.

## Design

### Architecture

A new `Signal::EntryQualityFilter` class sits between signal generation and strike selection in `Signal::Engine.run_for`. It receives the signal context (candles, Supertrend result, ADX, direction, market regime) and returns a pass/fail decision with a quality score.

Two-tier filtering:
1. **Hard gates** — absolute blockers, any failure = immediate rejection
2. **Quality scoring** — 5 components scored 0-100, must meet configurable minimum threshold

The filter result (score + breakdown) is stored in `entry_metadata` on the PositionTracker for post-trade analysis.

### Signal::Engine Integration Point

`Signal::Engine.run_for` has two code paths:

1. **Supertrend-only path** (lines ~47-97): Used when `entry_strategy == 'supertrend_adx'` or in exit_testing mode. Calculates Supertrend + ADX, decides direction, runs `comprehensive_validation`, detects regime.

2. **Multi-indicator path** (lines ~98-287): Full pipeline with SMC, multi-timeframe, etc.

The quality filter applies to **both paths**, inserted after validation and regime detection but before strike selection:

**Supertrend-only path:** Insert after regime detection (~line 96), before the `next unless direction` check and strike selection.

**Multi-indicator path:** Insert after `comprehensive_validation` (~line 290), before `EntryFilterEngine` call (~line 302).

```
Signal::Engine.run_for flow (both paths):
  1. Fetch candles, calculate Supertrend + ADX     (existing, unchanged)
  2. Decide direction                               (existing, unchanged)
  3. Comprehensive validation + regime detection    (existing, unchanged)
  4. ★ EntryQualityFilter.evaluate ★               (NEW)
     → Hard gates check → Scoring → pass/fail
  5. [Multi-indicator only] EntryFilterEngine       (existing, unchanged)
  6. Strike selection                               (existing, only if step 4 passes)
  7. EntryGuard.try_enter                          (existing, unchanged)
```

If the filter rejects the signal, strike selection and entry are skipped entirely.

**Note on EntryFilterEngine overlap:** In multi-indicator mode, `EntryFilterEngine` runs AFTER the quality filter and checks BOS + range expansion + ATR rising as hard gates. The quality filter scores BOS and range expansion but does not hard-gate them. A signal could pass the quality filter (high ADX + strong candle compensating for no BOS) but then get blocked by `EntryFilterEngine`. This is acceptable — the quality filter is a pre-filter that catches weak signals early; `EntryFilterEngine` remains a second defense layer. In future iterations, `EntryFilterEngine` could be absorbed into the quality filter.

### Exit Testing Mode Behavior

When `run_mode: exit_testing` or `entry_quality.enforce: false`, the filter still runs and logs the result but always returns `pass: true`. This preserves loose entry behavior for exit testing while providing visibility into what the filter would have done.

## Hard Gates

All must pass. Any failure = immediate rejection with logged reason.

### Gate 1: ADX Minimum Strength

**Threshold:** ADX ≥ 20 (raised from current 15)

**Rationale:** ADX 15-20 correlates with weak, directionless markets. Historical analysis shows significantly lower win rates in this range. Per-index overrides supported (SENSEX: 22).

**Config:** `entry_quality.gates.min_adx: 20`

### Gate 2: Market Regime Not CHOPPY

**Condition:** `regime.to_s.upcase != 'CHOPPY'`

**Rationale:** The regime detector (`Signal::Engine.detect_market_regime`) returns uppercase Strings like `'CHOPPY'`, `'RANGING'`, `'TRENDING_UP'`, `'TRENDING_DOWN'`. The filter normalizes via `.to_s.upcase` to handle both String and Symbol inputs safely. CHOPPY regime means rapid directionless oscillation — Supertrend flips are unreliable in this state. RANGING is allowed but penalized in scoring.

**Config:** `entry_quality.gates.block_choppy_regime: true`

### Gate 3: Supertrend Flip Candle Body Quality

**Threshold:** `body_ratio ≥ 0.40` where `body_ratio = (close - open).abs / (high - low)`

**Rationale:** A Supertrend flip on a doji or indecision candle (tiny body, long wicks) signals market uncertainty, not conviction. Requiring ≥ 40% body-to-range ratio filters out weak flips. A candle with `high == low` (zero range) fails this gate.

**Config:** `entry_quality.gates.min_body_ratio: 0.40`

### Gate 4: Momentum Confirmation

**Condition:** Flip candle close is beyond the new Supertrend level.
- Bullish: `close > supertrend_value`
- Bearish: `close < supertrend_value`

**Rationale:** A Supertrend flip where the close barely touches or doesn't exceed the new level indicates a tentative crossover likely to reverse. Requiring the close to be past the level confirms actual momentum.

**Config:** `entry_quality.gates.require_momentum_confirm: true`

## Quality Scoring System

After passing all hard gates, the signal is scored 0-100 across 5 components. Must meet `min_score` threshold (default: 40) to proceed.

### Component 1: Candle Body Strength (0-25 points)

Beyond the 0.40 hard gate, stronger bodies score higher:

| Body Ratio | Points |
|-----------|--------|
| 0.40-0.55 | 10 |
| 0.55-0.70 | 18 |
| 0.70+ | 25 |

### Component 2: ADX Strength Bonus (0-20 points)

ADX already passed the ≥ 20 hard gate. Stronger trend = higher score:

| ADX Range | Points |
|-----------|--------|
| 20-25 | 5 |
| 25-35 | 12 |
| 35+ | 20 |

### Component 3: Break of Structure (0-20 points)

Re-uses logic from the existing `EntryFilterEngine` BOS check, but as a scoring contributor rather than a hard gate:

| Condition | Points |
|-----------|--------|
| Recent BOS confirmed in signal direction | 20 |
| No BOS but price making higher highs/lower lows (simple structure) | 10 |
| No structure confirmation | 0 |

**BOS check:** Uses `Entries::BosExtractor.last_confirmed_bos(series, direction)` which requires a `CandleSeries` object (the `series:` parameter). Falls back to comparing last 3 candles' highs/lows for simple structure break detection if BosExtractor is unavailable or raises.

### Component 4: Range Expansion (0-20 points)

Current candle range relative to 20-candle ATR average:

| Range vs ATR | Points |
|-------------|--------|
| ≥ 1.5× ATR | 20 |
| ≥ 1.2× ATR | 12 |
| ≥ 1.0× ATR | 5 |
| < 1.0× ATR | 0 |

**ATR source:** Uses the ATR array from the Supertrend result (`supertrend_result[:atr]`). The `Indicators::Supertrend` class computes and returns ATR as part of its output hash. The last non-nil element is used as the current ATR value. **If ATR is nil or zero** (insufficient candle data), this component scores 0 points — no division is performed.

### Component 5: Momentum Confirmation Strength (0-15 points)

How far beyond the Supertrend level the close is, measured as a fraction of ATR:

| Distance Beyond ST | Points |
|-------------------|--------|
| ≥ 0.5× ATR | 15 |
| ≥ 0.25× ATR | 10 |
| < 0.25× ATR | 3 |

**Calculation:**
- Bullish: `distance = (close - supertrend_value) / atr`
- Bearish: `distance = (supertrend_value - close) / atr`
- **If ATR is nil or zero**, this component scores 3 points (minimum, since momentum gate already passed).

### Minimum Score Threshold

**Default: 40/100**

A "decent" entry (score 40-60) requires at least moderate candle body + some ADX strength + one of BOS/range expansion. A "great" entry (70+) has strong conviction across multiple factors.

The threshold is configurable via `entry_quality.min_score` in `algo.yml`.

## Public Interface

### Signal::EntryQualityFilter.evaluate

```ruby
Signal::EntryQualityFilter.evaluate(
  series:,            # CandleSeries — primary candle series (has .candles array)
  supertrend_result:, # Hash — { trend:, last_value:, atr: [...], line: [...] }
  adx_value:,         # Float — current ADX reading (bare number, e.g. 23.5)
  direction:,         # Symbol — :bullish or :bearish
  regime:,            # String — 'TRENDING_UP', 'TRENDING_DOWN', 'RANGING', 'CHOPPY' (from regime detector)
  index_key:          # String — 'NIFTY', 'BANKNIFTY', 'SENSEX'
)
```

**Returns:**
```ruby
{
  pass: true,           # Boolean — whether signal should proceed
  score: 67,            # Integer — quality score 0-100
  gates: {              # Hash — each hard gate result
    adx: true,
    regime: true,
    body_ratio: true,
    momentum: true
  },
  breakdown: {          # Hash — per-component score
    candle_body: 18,
    adx_strength: 12,
    bos: 20,
    range_expansion: 12,
    momentum: 5
  },
  reject_reason: nil    # String or nil — reason for rejection (gate name or "score_below_threshold")
}
```

### Class Structure

```ruby
module Signal
  class EntryQualityFilter
    class << self
      def evaluate(series:, supertrend_result:, adx_value:, direction:, regime:, index_key:)
        config = load_config(index_key)
        candles = series&.candles || []

        # Phase 1: Hard gates
        gate_result = check_gates(candles, supertrend_result, adx_value, direction, regime, config)
        return gate_result unless gate_result[:pass]

        # Phase 2: Scoring
        score_result = calculate_score(candles, supertrend_result, adx_value, direction, series, config)

        pass = score_result[:score] >= config[:min_score]
        log_result(index_key, direction, gate_result, score_result, pass)

        {
          pass: pass,
          score: score_result[:score],
          gates: gate_result[:gates],
          breakdown: score_result[:breakdown],
          reject_reason: pass ? nil : "score_below_threshold (#{score_result[:score]} < #{config[:min_score]})"
        }
      end
    end
  end
end
```

## Configuration

### config/algo.yml — New `entry_quality:` section

```yaml
entry_quality:
  enforce: true                      # false = log-only mode (no blocking)
  min_score: 40                      # minimum quality score to enter (0-100)
  gates:
    min_adx: 20                      # hard gate: minimum ADX value
    block_choppy_regime: true        # hard gate: block CHOPPY regime
    min_body_ratio: 0.40             # hard gate: minimum candle body/range ratio
    require_momentum_confirm: true   # hard gate: close must be beyond Supertrend level
  scoring:
    candle_body_weight: 25           # max points for candle body strength
    adx_strength_weight: 20          # max points for ADX bonus
    bos_weight: 20                   # max points for break of structure
    range_expansion_weight: 20       # max points for range expansion
    momentum_weight: 15              # max points for momentum strength
  index_overrides:
    SENSEX:
      min_adx: 22                    # SENSEX is noisier, needs higher ADX
```

**Scoring weight config values** represent the maximum points for each component. The tier tables in the scoring section are fixed proportions of that maximum. For example, if `candle_body_weight` is changed from 25 to 30, the tiers scale proportionally: 0.40-0.55 → 12 points (40% of 30), 0.55-0.70 → 22 points (72% of 30), 0.70+ → 30 points (100% of 30).

**Config absent handling:** If the `entry_quality` key is entirely missing from `algo.yml`, the filter defaults to `enforce: false` (log-only, no blocking). This ensures backward compatibility — existing deployments without the config key will not break. The `load_config` method provides sensible defaults for all values.

### config/profiles/exit_testing.yml — Override

```yaml
entry_quality:
  enforce: false                     # log-only in exit testing mode
```

## Changes

### Files Modified

| File | Change |
|------|--------|
| `app/services/signal/entry_quality_filter.rb` | **NEW** — hard gates + scoring filter |
| `app/services/signal/engine.rb` | Add ~15 lines: call `EntryQualityFilter.evaluate` after validation, store result in `entry_metadata` |
| `config/algo.yml` | Add `entry_quality:` section |
| `config/profiles/exit_testing.yml` | Add `entry_quality.enforce: false` |

### Files NOT Modified

- `entries/entry_guard.rb` — no changes to the guard pipeline
- `entries/entry_guard_pipeline.rb` — guards remain unchanged
- `signal/entry_filter_engine.rb` — existing filter engine unchanged (quality filter is separate)
- Exit logic files — no changes
- Position sizing — no changes

## Testing Strategy

### Unit tests (`spec/services/signal/entry_quality_filter_spec.rb`)

**Hard gate tests:**
- ADX 17 → reject with `reject_reason: "min_adx"`
- ADX 22 → pass gates
- CHOPPY regime → reject with `reject_reason: "regime"`
- RANGING regime → pass gates (penalized in scoring)
- Doji candle (body_ratio 0.1) → reject with `reject_reason: "body_ratio"`
- Strong candle (body_ratio 0.6) → pass gates
- Close below Supertrend on bullish flip → reject with `reject_reason: "momentum"`
- Close above Supertrend on bullish flip → pass gates
- Zero-range candle (high == low) → reject with `reject_reason: "body_ratio"`

**Scoring tests:**
- Known inputs → expected per-component scores
- Score 39 → `pass: false`
- Score 40 → `pass: true`
- Maximum score scenario (all components maxed) → 100
- Minimum passing scenario → exactly 40

**Config tests:**
- Per-index override applied correctly (SENSEX min_adx: 22)
- `enforce: false` → always `pass: true` regardless of score
- Custom min_score threshold respected

**Edge cases:**
- nil series or empty candles → reject gracefully with `pass: false, reject_reason: "no_candle_data"`
- nil ADX → reject at ADX gate
- nil supertrend_result → reject gracefully with `pass: false, reject_reason: "no_supertrend_data"`
- Single candle (no ATR history) → pass gates if candle is valid, score range/momentum as 0
- Zero ATR → score range_expansion and momentum as 0 (no division by zero)
- `entry_quality` config key absent → defaults to `enforce: false` (log-only)

### Post-deploy validation

After running paper mode for a trading session:
- Check PositionTracker metadata for `entry_quality_score` and `entry_quality_breakdown`
- Correlate scores with PnL outcomes
- Verify rejection logs appear for filtered signals
- Tune `min_score` threshold based on observed score distribution
