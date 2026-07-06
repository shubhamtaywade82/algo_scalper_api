# 10 — Deferred Track: Greeks Engine & Indicator Streaming

Both target-diagram boxes ("Greeks Engine", incremental "Indicator Engine") are **deliberately
deferred**. This doc records why, and the concrete triggers that would reopen them (Phase 7).

## 1. Greeks / IV computation — D-10.1: SKIP for v1 (user-confirmed)

### Current state

- Greeks (delta/gamma/theta/vega) are **broker-provided**: `Options::ChainAnalyzer` reads them
  from the DhanHQ option-chain payload (`option_data['greeks']`). The chain adapter
  (`app/services/adapters/option_chain/dhan_adapter.rb`) is live even in paper mode.
- IV is **recorded and ranked, not derived**: `iv_snapshots` table (daily ATM IV per index) +
  `Options::IvRankTracker` (rank/percentile) + `PreMarketIvBaselineJob`.
- There is **no Black-Scholes / IV solver anywhere** in the codebase (verified: no
  `black_scholes`/`norm_cdf`/`d1`/Newton–bisection hits).

### Why skip

- Strike selection, qualification scoring, gamma-ramp/delta-acceleration detection, and IV-rank
  gating all work today from broker greeks — no live-trading capability is blocked.
- A local solver adds real surface area (dividend/rate assumptions, expiry-day annualization
  edge cases, IV root-finding stability at deep ITM/OTM) for zero live-path benefit.
- The one genuine consumer would be **replay/backtest** (historical sessions lack chain-greek
  snapshots) — and current replay fidelity relies on `Backtest::OptionTradeSimulator`'s premium
  model, which is the accepted approximation (see [09](09_risks_and_change_policy.md) open
  questions).

### Revisit triggers (reopen as Phase 7 work)

1. Replay/backtest results are demonstrably misleading because premium evolution lacks
   greek-based modeling (e.g. theta decay on expiry-day scalps materially misprices exits).
2. A strategy's alpha explicitly needs greeks the broker doesn't supply (e.g. custom vol
   surface, forward IV).
3. DhanHQ chain greeks become unreliable/absent (would also qualify as a CLAUDE.md Critical
   Scenario 1).

### If built

Small, pure module — `Options::Greeks::BlackScholes` (price, greeks, implied vol via
Newton-with-bisection-fallback), consuming `iv_snapshots`/chain IV as seeds; wired only into
replay context building. No live-path changes.

## 2. Incremental (streaming) indicators — D-10.2: DEFER

### Current state

- `app/services/indicators/` uses a batch model: `BaseIndicator#calculate_at(index)` /
  `ready?(index)` over a full `CandleSeries` (in-memory, `MAX_CANDLES = 200`), recomputed per
  evaluation. `CachedIndicatorSource` mitigates refetch cost via `Live::CandleSeriesCache`.

### Why defer

- At the platform's actual load — a handful of index instruments, 1m bars, ~200-candle windows,
  strategies waking once per minute — batch recompute is microseconds-to-milliseconds. There is
  no measured latency problem to solve.
- The plugin boundary hides the implementation: strategies call `context.indicators.supertrend`
  etc., so a later swap to streaming is invisible to every plugin.

### Revisit triggers

1. Strategy count × instrument count × timeframe fan-out makes per-bar recompute measurably slow
   (budget: context build should stay < 50ms; profile when > 10 running strategies or
   sub-minute timeframes arrive).
2. Tick-granularity strategies (per-tick `#call`) become a requirement — batch recompute per tick
   would be genuinely wasteful.

### If built

Introduce an `IndicatorStream` facade the `ContextBuilder` consumes (same accessor surface).
Migration priority by usage: **Supertrend → EMA → RSI → ADX** (Supertrend + ADX are the live
signal path's hot pair; EMA/RSI next by strategy-template usage). Each streaming implementation
must be property-tested against its batch counterpart over recorded sessions (identical outputs)
before swap-in — same parity discipline as the Phase-2 strategy extraction.

## 3. Relationship to the roadmap

Phase 7 in [08](08_migration_roadmap.md) exists solely for these two items. Entering it requires a
documented trigger from the lists above plus profiling numbers; otherwise the phase closes as
**skipped** and this doc gets a dated closure note.
