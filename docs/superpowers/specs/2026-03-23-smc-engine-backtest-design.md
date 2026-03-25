# SMC Unified Engine + Backtester — Design Spec

**Date:** 2026-03-23
**Status:** Approved

## Problem

The current SMC implementation is distributed across `Smc::BiasEngine`, `Smc::Navigator`,
`Smc::Context`, `Smc::Analyzer`, `Smc::SmcPermissionResolver`, `Smc::ZoneEngine`,
`Smc::LiquidityEngine`, and `Smc::StructureEngine`. This makes the logic hard to reason
about, hard to test in isolation, and impossible to replay against historical data.

There is no way to rigorously validate whether SMC signals improve entries before enabling
them in live trading.

## Goals

1. Collapse all SMC orchestration into a single `Smc::Engine` (keep detector leaf classes unchanged).
2. Build `Smc::Backtester` that replays historical data bar-by-bar through the engine and reports both signal accuracy and simulated trade P&L.
3. Keep the entire system isolated from the current live pipeline and exit_testing mode during the backtest phase.
4. Design the engine's output contract so it can be wired into the live pipeline in a future phase with minimal diff.

## Out of Scope (Phase 1)

- Modifying any existing `Smc::*` files
- Wiring `Smc::Engine` into `Signal::Engine`, `SmcNavigatorGuard`, or `Smc::Scanner`
- Any changes to `config/algo.yml`
- Changing exit_testing mode behaviour

---

## Architecture

### Detector Leaf Classes (unchanged)

The following stay exactly as-is — they are pure, series-in / result-out classes:

- `Smc::Detectors::Structure`
- `Smc::Detectors::Fvg`
- `Smc::Detectors::Liquidity`
- `Smc::Detectors::OrderBlocks`
- `Smc::Detectors::PremiumDiscount`
- `Smc::Detectors::InternalStructure`

**Important:** `Smc::Engine` calls detector classes directly. It must NOT use `Smc::Context`
as a shortcut — `Context` instantiates `Smc::Analyzer` which writes to `Smc::StructureStore`
(a Redis-backed store). Using `Context` would silently break the isolation guarantee.

### New Files

| File | Responsibility |
|------|----------------|
| `app/services/smc/engine.rb` | Single public entry point; orchestrates detectors across HTF/MTF/LTF; returns `Decision` |
| `app/services/smc/engine/decision.rb` | Immutable result struct with all fields needed by live pipeline and backtester |
| `app/services/smc/engine/confluence_scorer.rb` | Combines HTF/MTF/LTF detector outputs into a single confidence score (0.0–1.0) |
| `app/services/smc/engine/permission_tier.rb` | Maps confidence + bias to `:blocked / :execution_only / :scale_ready / :full_deploy` |
| `app/services/smc/backtester.rb` | Fetches historical OHLC, replays bar-by-bar, records accuracy + simulated trades |
| `app/services/smc/backtest_result.rb` | Value object holding all backtest output (stats, per-signal rows) |
| `lib/tasks/smc_backtest.rake` | Rake task: `rails smc:backtest[NIFTY,30]` |
| `spec/services/smc/engine_spec.rb` | Unit tests for Engine |
| `spec/services/smc/backtester_spec.rb` | Unit tests for Backtester |

---

## Smc::Engine

### Public Interface

```ruby
# Pure function: series in, Decision out. No DhanHQ calls, no AlgoConfig reads.
Smc::Engine.analyze(htf:, mtf:, ltf:, direction: nil)
# => Smc::Engine::Decision
```

**Parameters:**
- `htf` — `CandleSeries` at 60m (≥ 20 candles recommended)
- `mtf` — `CandleSeries` at 15m (≥ 50 candles recommended)
- `ltf` — `CandleSeries` at 5m (≥ 50 candles recommended)
- `direction` — `:bullish` / `:bearish` / `nil`; when nil, engine derives from HTF structure

### Minimum Data Guard

If **any** of the three series has fewer than 8 candles, return immediately:
```ruby
Decision.new(
  bias: :no_trade, allow_entry: false, confidence: 0.0,
  exit_signal: false, exit_reason: nil, exit_confidence: 0.0,
  permission: :blocked, phase: :insufficient_data,
  direction_used: nil, details: {}
)
```

### Conflicting Direction Guard

If `direction` is explicitly provided **and** it conflicts with the HTF macro trend (e.g.,
`:bullish` passed but HTF structure is `:bearish`), return immediately:
```ruby
Decision.new(
  bias: :no_trade, allow_entry: false, confidence: 0.0,
  permission: :blocked, phase: :direction_conflict,
  direction_used: direction, ...
)
```
No scoring is performed. This is a hard-block, not a confidence reduction.

### Internal Analysis Pass (one pass, three layers)

**Layer 1 — HTF (60m): Zone + Macro Trend**
- Run `Detectors::Structure` → macro trend (`:bullish` / `:bearish` / `:range`)
- Run `Detectors::PremiumDiscount` → zone (`:premium` / `:discount` / `:equilibrium`)
- Derive `htf_bias`:
  - `:call` if trend is `:bullish` AND zone is `:discount`
  - `:put`  if trend is `:bearish` AND zone is `:premium`
  - `:no_trade` otherwise (ranging, or trend/zone misalignment)
- If `direction` was `nil`, derive `direction_used` from `htf_bias`:
  - `:call` → `:bullish`, `:put` → `:bearish`, `:no_trade` → `nil`
- If `htf_bias == :no_trade` and `direction` was nil: skip zone scoring (no direction to be correct relative to)

**Layer 2 — MTF (15m): Structure Alignment**
- Run `Detectors::Structure` → MTF trend + BOS/CHoCH events
- Run `Detectors::Liquidity` → recent sweep events
- `mtf_aligned`: true if MTF trend matches `direction_used` OR MTF shows CHoCH in `direction_used` direction
- `mtf_choch_against`: true if MTF shows CHoCH opposing `direction_used`

**Layer 3 — LTF (5m): Entry Timing**
- Run `Detectors::Structure` → LTF trend
- Run `Detectors::Fvg` → active FVGs
- Run `Detectors::OrderBlocks` → nearest OB to current price
- Run `Detectors::Liquidity` → recent sweep (stop hunt confirmation)
- Determine `phase` (first matching):
  1. `:liquidity_sweep` — liquidity sweep present on LTF
  2. `:fvg_mitigation` — price is inside an active FVG
  3. `:ob_retest` — price is within 0.5× ATR of nearest OB
  4. `:displacement` — LTF trend aligned, no specific structure yet
  5. `:none` — no qualifying condition

Note on `:trap_detected` (from the existing `Smc::Analyzer`): in the existing system a
liquidity sweep is labeled `:trap_detected` and is treated as a positive entry signal.
In the new engine, this signal is captured by the `:liquidity_sweep` phase and the
`+0.12` liquidity score. There is no separate trap-detected penalty — the liquidity
bonus covers it already.

### Confluence Scoring (`Smc::Engine::ConfluenceScorer`)

Scoring applies only when `direction_used` is not nil. If `direction_used` is nil
(all-ranging market), skip to permission tier with `confidence: 0.0`.

| Condition | Points | Notes |
|-----------|--------|-------|
| HTF trend aligned with `direction_used` | +0.20 | |
| MTF trend aligned | +0.15 | |
| LTF trend aligned | +0.10 | |
| Price in correct zone (discount for bullish, premium for bearish) | +0.18 | Only scored when `htf_bias != :no_trade` |
| Active FVG in direction | +0.12 | 0 if no active FVG |
| Liquidity sweep confirmed on LTF | +0.12 | 0 if no sweep |
| Order block proximity (within 0.5× ATR) | +0.08 | 0 if no OB present |
| CHoCH against `direction_used` on MTF | −0.15 | |

Baseline: 0.05. Maximum: 0.05 + 0.95 = 1.00. Clamped 0.0–1.0.

Individual detector failures are rescued and treated as 0 contribution (no raise).

### Permission Tier (`Smc::Engine::PermissionTier`)

`bias == :no_trade` always yields `:blocked`, regardless of confidence.

| Confidence (when `bias != :no_trade`) | Permission |
|---------------------------------------|------------|
| < 0.40 | `:blocked` |
| 0.40–0.54 | `:execution_only` |
| 0.55–0.69 | `:scale_ready` |
| ≥ 0.70 | `:full_deploy` |

`allow_entry` is `true` only when `permission != :blocked`.

### Exit Signal

Evaluated on LTF detectors (same run, no extra fetch):
- `exit_signal: true` + `exit_confidence: 0.72` if LTF structure shows CHoCH against `direction_used`
- `exit_signal: true` + `exit_confidence: 0.65` if LTF liquidity sweep on the side opposing `direction_used`
- `exit_signal: false` otherwise

Exit signal is independent of `allow_entry` — it is valid even when the engine would not
allow a new entry (e.g., for managing an existing position when confidence has dropped).

### Decision Struct

```ruby
Smc::Engine::Decision = Struct.new(
  :bias,             # :call / :put / :no_trade
  :allow_entry,      # Boolean
  :confidence,       # Float 0.0–1.0
  :exit_signal,      # Boolean
  :exit_reason,      # :structure_inversion / :liquidity_sweep / nil
  :exit_confidence,  # Float
  :permission,       # :blocked / :execution_only / :scale_ready / :full_deploy
  :phase,            # :liquidity_sweep / :fvg_mitigation / :ob_retest / :displacement / :none / :insufficient_data / :direction_conflict
  :direction_used,   # :bullish / :bearish / nil (resolved direction actually used for scoring)
  :details,          # Hash — full per-layer breakdown
  keyword_init: true
)
```

**`details` hash shape:**
```ruby
{
  htf: { trend:, zone:, bias: },
  mtf: { trend:, aligned:, choch_against: },
  ltf: { trend:, phase:, fvg_active:, ob_proximity:, liquidity_sweep: },
  scores: { htf_trend:, mtf_trend:, ltf_trend:, zone:, fvg:, liquidity:, ob:, choch_penalty:, baseline: }
}
```

### Error Handling

- Engine never raises — always returns a `Decision`
- Detector failures inside a layer are rescued; that layer's score contribution becomes 0
- If the entire HTF/MTF/LTF run raises unexpectedly: return minimum-data-guard `Decision`

### Isolation Guarantee

`Smc::Engine` has **zero dependencies** on:
- `AlgoConfig`
- `Rails.cache`
- `ActionCable`
- DhanHQ API
- `Smc::Context`, `Smc::Analyzer`, `Smc::BiasEngine`, `Smc::Navigator`
- `Smc::StructureStore` (Redis-backed — never touch from this engine)

---

## Smc::Backtester

### Public Interface

```ruby
Smc::Backtester.run(
  instrument:,          # Instrument record
  days_back: 30,        # Calendar days of history to fetch
  direction: nil,       # nil = engine derives; :bullish / :bearish to force
  stop_pct: 0.30,       # Hard stop as fraction of premium (0.30 = 30% loss)
  target_pct: 0.60,     # Profit target as fraction of premium (0.60 = 60% gain)
  lookahead_bars: 5     # LTF bars forward for accuracy check
)
# => Smc::BacktestResult
# Returns a failed BacktestResult (with error:) if instrument.intraday_ohlc returns nil
```

If `instrument.intraday_ohlc` returns nil for any timeframe, the backtester returns a
`BacktestResult` with `error: "Failed to fetch #{interval} OHLC data"` and zero stats.
It does not raise.

### Data Fetching

Fetches three independent OHLC histories from DhanHQ upfront (three API calls, one per tf):
```ruby
htf_candles = instrument.intraday_ohlc(interval: '60', days: days_back)  # may return nil
mtf_candles = instrument.intraday_ohlc(interval: '15', days: days_back)
ltf_candles = instrument.intraday_ohlc(interval: '5',  days: days_back)
```

All candles are sorted chronologically after fetch. No live feed, no tick cache, no Redis reads.

### Bar-by-Bar Replay

Walk forward one LTF bar at a time. Start at index 49 (ensures at least 50 LTF candles
in the first window — the minimum for reliable indicator calculation).

**Timestamp boundary rule (no lookahead):**

For each LTF bar at index `i` with timestamp `ts`:
- `ltf_series` = candles `[max(0, i−149)..i]` (≤ 150 candles)
- `mtf_series` = MTF candles where `timestamp < floor(ts, 15min)` — strictly less than the
  open of the enclosing 15m candle. Last 100 candles of the filtered set.
- `htf_series` = HTF candles where `timestamp < floor(ts, 60min)` — strictly less than the
  open of the enclosing 60m candle. Last 60 candles of the filtered set.

`floor(ts, N_minutes)` means truncate `ts` to the nearest `N`-minute boundary:
`ts - (ts.to_i % (N * 60))`.

This ensures the currently-forming MTF/HTF candle is never included.

If `mtf_series` or `htf_series` has fewer than 8 candles after filtering, skip this bar
(the engine will return `:insufficient_data` — do not record as a signal).

```ruby
decision = Smc::Engine.analyze(htf: htf_series, mtf: mtf_series, ltf: ltf_series, direction:)
```

### Accuracy Track

When `decision.allow_entry == true` and `decision.bias != :no_trade`:
- Look forward `lookahead_bars` LTF candles from index `i`
- Determine if price moved ≥ 0.5× current ATR in `direction_used`
- Record: `correct: bool`, `actual_move_pct: float`, `confidence_at_signal: float`,
  `permission_at_signal: symbol`

### Trade Simulation Track

One simulated position at a time (no pyramiding):

- **No position** — open trade on first bar where `allow_entry: true` (entry price = LTP = `ltf_candles[i].close`)
- **In position** — on each subsequent bar evaluate in priority order:
  1. `decision.exit_signal == true` → close at LTP (exit_reason: `:smc_exit`)
  2. LTP ≤ `entry_price × (1 − stop_pct)` → close (exit_reason: `:stop`)
  3. LTP ≥ `entry_price × (1 + target_pct)` → close (exit_reason: `:target`)
  4. End of data → close at last LTP (exit_reason: `:end_of_data`)
- Record: `entry_ts`, `exit_ts`, `entry_price`, `exit_price`, `pnl_pct`, `hold_bars`, `exit_reason`

### Baseline Comparison

After the SMC run, generate a second pass over the same candle data using naive random-entry:
- Enter on every 10th LTF bar regardless of SMC state (same stop/target/simulation logic)
- Baseline does NOT use `Smc::Engine` at all — it is a fixed-interval entry
- Records the same trade stats as the real run

The baseline establishes the null hypothesis win rate for the period.

### Output — `Smc::BacktestResult`

```ruby
{
  instrument: 'NIFTY',
  error: nil,                      # String if data fetch failed, nil on success
  period: { from:, to:, days_back:, total_ltf_bars:, signals_evaluated: },
  accuracy: {
    total_signals:, correct:, win_rate:,
    avg_move_pct:, avg_confidence_on_win:, avg_confidence_on_loss:
  },
  simulation: {
    total_trades:, winners:, losers:, win_rate:,
    total_pnl_pct:, avg_pnl_pct:, max_drawdown_pct:,
    avg_hold_bars:,
    exit_reasons: { smc_exit:, stop:, target:, end_of_data: }
  },
  baseline: {
    total_trades:, winners:, losers:, win_rate:, total_pnl_pct:
  },
  signals: [  # per-signal rows — written to CSV
    {
      ts:, bias:, confidence:, permission:, phase:, allow_entry:,
      correct:, actual_move_pct:,           # accuracy track
      trade_pnl_pct:, exit_reason:          # simulation track (nil if no trade opened)
    }
  ]
}
```

---

## Rake Task

```bash
# Basic usage (engine derives direction from HTF)
rails smc:backtest[NIFTY,30]

# Forced direction
rails smc:backtest[BANKNIFTY,14,bearish]

# Custom stop/target
rails smc:backtest[NIFTY,30,nil,0.25,0.50]
```

Prints summary to stdout. Writes per-signal CSV to `tmp/smc_backtest_NIFTY_20260323.csv`.

---

## Testing

### `spec/services/smc/engine_spec.rb`

- Returns a `Decision` struct with all expected fields present
- Returns `permission: :blocked`, `allow_entry: false`, `confidence: 0.0` when any series has fewer than 8 candles
- Returns `permission: :blocked`, `phase: :direction_conflict` when explicit direction conflicts with HTF trend
- Returns `bias: :no_trade`, `permission: :blocked` when HTF market is ranging and `direction: nil`
- Returns `allow_entry: false` when `direction` opposes HTF trend (separate from direction_conflict guard — this tests the scoring path rejecting misaligned direction)
- `direction_used` is populated from HTF bias when `direction: nil` is passed and HTF is trending
- `direction_used` is nil when HTF is ranging and `direction: nil`
- Confidence increases step-by-step as each aligned signal is added (trend, zone, liquidity)
- CHoCH-against-direction on MTF (−0.15 penalty) reduces confidence enough to demote `scale_ready` → `execution_only`
- Zone score is 0 when `htf_bias == :no_trade` (no direction to be correct relative to)
- OB score is 0 when no active order block is present (not defaulted to +0.08)
- `exit_signal: true` with `exit_confidence: 0.72` when LTF CHoCH against direction
- `exit_signal: true` with `exit_confidence: 0.65` when LTF opposite liquidity sweep
- Exit signal fires even when `allow_entry: false` (position management use case)
- Permission tiers: `confidence: 0.39 → :blocked`, `0.40 → :execution_only`, `0.55 → :scale_ready`, `0.70 → :full_deploy`
- `bias: :no_trade` always yields `permission: :blocked` regardless of confidence value
- Never raises on malformed or empty series input

### `spec/services/smc/backtester_spec.rb`

- Rolling MTF/HTF windows contain only candles with timestamp strictly before the enclosing candle boundary (no lookahead)
- Skips bars where MTF or HTF series has fewer than 8 candles after timestamp filtering
- Accuracy track records `correct: true` when price moves ≥ 0.5× ATR in signal direction within `lookahead_bars`
- Stop triggers when LTP ≤ `entry_price × (1 − stop_pct)` — records `exit_reason: :stop`
- Target triggers when LTP ≥ `entry_price × (1 + target_pct)` — records `exit_reason: :target`
- SMC exit triggers when `decision.exit_signal == true` — records `exit_reason: :smc_exit`
- Baseline pass enters on every 10th bar, does not call `Smc::Engine`
- Returns `BacktestResult` with `error:` message when `intraday_ohlc` returns nil; does not raise
- `BacktestResult#signals` contains one row per bar where `allow_entry: true`

---

## Future Live Integration (Phase 2 — separate PR)

When backtest validates the engine, wire it in via a config flag:

```yaml
# config/algo.yml
signals:
  smc_engine_v2: false   # flip true to route live pipeline through Smc::Engine
```

Three connection points, each a small diff:

**`SmcNavigatorGuard`** — replace `Smc::Navigator.evaluate_entry` call:
```ruby
decision = Smc::Engine.analyze(htf: ..., mtf: ..., ltf: ..., direction: direction)
return { blocked: "smc:no_trade" }         unless decision.allow_entry
return { blocked: 'smc:low_confidence' }   if decision.confidence < min_confidence
EntryGuardPipeline::PASS
```
Note: use a static block reason (`"smc:no_trade"`) rather than `decision.exit_reason`
(which is nil during entry evaluation and would produce `"smc:"`).

**`Signal::Engine`** — replace `BiasEngine.decision` call:
```ruby
decision = Smc::Engine.analyze(htf: ..., mtf: ..., ltf: ...)
smc_decision = decision.bias   # :call / :put / :no_trade — same vocabulary as current BiasEngine
```

**`Smc::Scanner`** — replace `BiasEngine.new.decision` call with `Smc::Engine.analyze`;
use `decision.bias` and `decision.details` for Telegram alert content.

Old distributed classes (`BiasEngine`, `Navigator`, `Context`, `Analyzer`,
`SmcPermissionResolver`) are deleted only after the new engine is validated in production.
