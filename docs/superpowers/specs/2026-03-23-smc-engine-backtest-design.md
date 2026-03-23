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

### New Files

| File | Responsibility |
|------|----------------|
| `app/services/smc/engine.rb` | Single public entry point; orchestrates detectors across HTF/MTF/LTF; returns `Decision` |
| `app/services/smc/engine/decision.rb` | Immutable result struct with all fields needed by live pipeline and backtester |
| `app/services/smc/engine/confluence_scorer.rb` | Combines HTF/MTF/LTF detector outputs into a single confidence score (0.0–1.0) |
| `app/services/smc/engine/permission_tier.rb` | Maps confidence + phase to `:blocked / :execution_only / :scale_ready / :full_deploy` |
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

### Internal Analysis Pass (one pass, three layers)

**Layer 1 — HTF (60m): Zone + Macro Trend**
- Run `Detectors::Structure` → macro trend (`:bullish` / `:bearish` / `:range`)
- Run `Detectors::PremiumDiscount` → zone (`:premium` / `:discount` / `:equilibrium`)
- Derive `htf_bias`: `:call` if bullish trend in discount; `:put` if bearish trend in premium; else `:no_trade`

**Layer 2 — MTF (15m): Structure Alignment**
- Run `Detectors::Structure` → MTF trend + BOS/CHoCH events
- Run `Detectors::Liquidity` → recent sweep events
- Check alignment: MTF trend matches HTF bias OR MTF shows CHoCH in HTF direction

**Layer 3 — LTF (5m): Entry Timing**
- Run `Detectors::Structure` → LTF trend
- Run `Detectors::Fvg` → active FVGs (pullback targets)
- Run `Detectors::OrderBlocks` → nearest OB to current price
- Run `Detectors::Liquidity` → recent sweep (stop hunt confirmation)
- Determine entry phase: `:displacement` / `:fvg_mitigation` / `:ob_retest` / `:liquidity_sweep` / `:none`

**Confluence Scoring (`Smc::Engine::ConfluenceScorer`):**

| Condition | Points |
|-----------|--------|
| HTF trend aligned with direction | +0.20 |
| MTF trend aligned | +0.15 |
| LTF trend aligned | +0.10 |
| Price in correct zone (discount for call, premium for put) | +0.18 |
| Active FVG in direction | +0.12 |
| Liquidity sweep confirmed | +0.12 |
| Order block proximity (within 0.5× ATR) | +0.08 |
| Phase is `:trap_detected` (penalty) | −0.12 |
| CHoCH against direction on MTF | −0.15 |

Baseline: 0.05 (never zero even with no signals). Score clamped 0.0–1.0.

**Permission Tier (`Smc::Engine::PermissionTier`):**

| Confidence | Permission |
|------------|------------|
| < 0.40 | `:blocked` |
| 0.40–0.54 | `:execution_only` |
| 0.55–0.69 | `:scale_ready` |
| ≥ 0.70 | `:full_deploy` |

**Exit Signal:**
- `exit_signal: true` if LTF structure inverts against `direction` (CHoCH) OR liquidity swept on opposite side
- `exit_confidence`: 0.72 for structure inversion, 0.65 for liquidity sweep

### Decision Struct

```ruby
Smc::Engine::Decision = Struct.new(
  :bias,          # :call / :put / :no_trade
  :allow_entry,   # Boolean — true if permission != :blocked AND direction aligned
  :confidence,    # Float 0.0–1.0 from ConfluenceScorer
  :exit_signal,   # Boolean
  :exit_reason,   # Symbol (:structure_inversion / :liquidity_sweep / nil)
  :exit_confidence, # Float
  :permission,    # :blocked / :execution_only / :scale_ready / :full_deploy
  :details,       # Hash — full per-layer breakdown for logging and CSV
  keyword_init: true
)
```

**`details` hash shape:**
```ruby
{
  htf: { trend:, zone:, bias: },
  mtf: { trend:, aligned:, choch:, liquidity_sweep: },
  ltf: { trend:, phase:, fvg_active:, ob_proximity:, liquidity_sweep: },
  scores: { htf_trend:, mtf_trend:, ltf_trend:, zone:, fvg:, liquidity:, ob:, penalties: },
  direction_input: # :bullish / :bearish / nil
}
```

### Error Handling

- If any series has fewer than 8 candles: return `Decision` with `allow_entry: false`, `permission: :blocked`, `confidence: 0.0`, `bias: :no_trade`
- Individual detector failures are rescued and treated as neutral (no contribution to score)
- Engine never raises — always returns a `Decision`

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
  lookahead_bars: 5     # Bars forward for accuracy check
)
# => Smc::BacktestResult
```

### Data Fetching

Fetches three independent OHLC histories from DhanHQ:
```ruby
htf_candles = instrument.intraday_ohlc(interval: '60', days: days_back)
mtf_candles = instrument.intraday_ohlc(interval: '15', days: days_back)
ltf_candles = instrument.intraday_ohlc(interval: '5',  days: days_back)
```

All fetched once upfront. No live feed, no tick cache, no Redis reads.

### Bar-by-Bar Replay

Walk forward one LTF bar at a time (minimum index 49 to ensure enough history):

```
for each ltf index i from 49 to ltf_candles.length - 1:
  ltf_series = CandleSeries from ltf_candles[max(0, i-149)..i]   (≤ 150 candles)
  ts         = ltf_candles[i].timestamp

  mtf_series = CandleSeries from mtf_candles where timestamp ≤ ts (last 100)
  htf_series = CandleSeries from htf_candles where timestamp ≤ ts (last 60)

  decision   = Smc::Engine.analyze(htf: htf_series, mtf: mtf_series, ltf: ltf_series, direction:)

  record(bar: i, ts: ts, decision: decision, ltp: ltf_candles[i].close)
```

No lookahead — each window only contains candles available at that bar's timestamp.

### Accuracy Track

When `decision.allow_entry == true` and `decision.bias != :no_trade`:
- Look forward `lookahead_bars` LTF bars
- Check if close moved ≥ 0.5× ATR in the signalled direction
- Record: `correct: bool`, `actual_move_pct: float`, `confidence_at_signal: float`

### Trade Simulation Track

State machine per index:
- **No position**: open simulated trade on first `allow_entry: true` bar (entry price = LTP)
- **In position**: on each bar check:
  1. `decision.exit_signal == true` → close at LTP (reason: `smc_exit`)
  2. LTP dropped ≥ `stop_pct` from entry → close (reason: `stop`)
  3. LTP rose ≥ `target_pct` from entry → close (reason: `target`)
- Record: `entry_price, exit_price, pnl_pct, hold_bars, exit_reason`

One position at a time per instrument. No pyramiding.

### Baseline Comparison

After the real run, generate a second pass with `Smc::Engine` replaced by random entry signals
(entry on every 10th bar regardless of SMC state, same stop/target). This establishes a
baseline win rate to compare against.

### Output — `Smc::BacktestResult`

```ruby
{
  instrument: 'NIFTY',
  period: { from:, to:, days_back:, total_ltf_bars: },
  accuracy: {
    total_signals:, correct:, win_rate:,
    avg_move_pct:, avg_confidence_on_win:, avg_confidence_on_loss:
  },
  simulation: {
    total_trades:, winners:, losers:, win_rate:,
    total_pnl_pct:, avg_pnl_pct:, max_drawdown_pct:,
    avg_hold_bars:,
    exit_reasons: { smc_exit:, stop:, target: }
  },
  baseline: {
    total_trades:, win_rate:, total_pnl_pct:
  },
  signals: [ # per-signal rows for CSV export
    { ts:, bias:, confidence:, permission:, allow_entry:,
      correct:, actual_move_pct:, trade_pnl_pct:, exit_reason: }
  ]
}
```

---

## Rake Task

```bash
# Basic usage
rails smc:backtest[NIFTY,30]

# With forced direction
rails smc:backtest[BANKNIFTY,14,bearish]

# Custom stop/target
rails smc:backtest[NIFTY,30,nil,0.25,0.50]
```

Output: prints result summary to stdout + writes per-signal CSV to `tmp/smc_backtest_NIFTY_20260323.csv`.

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
return { blocked: "smc:#{decision.exit_reason}" } unless decision.allow_entry
return { blocked: 'smc:low_confidence' } if decision.confidence < min_confidence
```

**`Signal::Engine`** — replace `BiasEngine.decision` call:
```ruby
decision = Smc::Engine.analyze(htf: ..., mtf: ..., ltf: ...)
smc_decision = decision.bias
```

**`Smc::Scanner`** — replace `BiasEngine.new.decision` call with `Smc::Engine.analyze`.

Old distributed classes (`BiasEngine`, `Navigator`, `Context`, `Analyzer`, `SmcPermissionResolver`)
are deleted only after the new engine is validated in production.

---

## Testing

### `spec/services/smc/engine_spec.rb`

- Returns `Decision` struct with correct fields
- `allow_entry: false` when fewer than 8 candles in any series
- `allow_entry: false` when direction opposes HTF trend
- Confidence increases with each additional aligned signal (trend + zone + liquidity)
- Permission tiers map correctly from confidence thresholds
- Exit signal fires on LTF CHoCH against direction
- Never raises on malformed series input

### `spec/services/smc/backtester_spec.rb`

- Builds rolling windows correctly (no lookahead)
- Accuracy track: records correct/incorrect based on lookahead_bars
- Trade simulation: stop triggers at stop_pct, target at target_pct, smc_exit on exit_signal
- Baseline: generates random-entry comparison
- Result struct contains all expected fields

---

## Isolation Guarantee

`Smc::Engine` has **no dependencies on**:
- `AlgoConfig`
- `Rails.cache`
- `ActionCable`
- DhanHQ API
- Any existing `Smc::*` orchestration class

`Smc::Backtester` depends only on `Instrument#intraday_ohlc` (DhanHQ data fetch) and `Smc::Engine`. It does not read `run_mode`, does not call `EntryGuard`, and does not touch live state.
