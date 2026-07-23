# Regime-driven signal generation + per-regime exit-strategy report

Date: 2026-07-20

## Context

Prior session fixed the ATM-drift bug in `Research::TradeScorer` (candidates
now lock to the entry bar's `actual_strike`) and wired `Research::ExitCaptureAnalyzer`'s
14 exit strategies into the `Research::Pipeline` → `OptionCandidate` path via
a new `exit_simulations` jsonb column, populated for every scored candidate.

Analysis of the existing (pre-fix) research artifact
(`data/research/v6_nifty_sensex/combined/research_report_v4.json`, 327 real
NIFTY+SENSEX ORB-breakout trades) showed: (a) only `mfe_retrace_25` has
positive expectancy of the 13 exit strategies tested, and it's thin
(+0.71% OOS, bootstrap CI barely excludes zero); (b) entry-side feature
importance (OR width, ignition velocity, ADX, RSI, VWAP distance, etc.) is
~0 across the board — none of it predicts which breakouts sustain; (c) the
edge, such as it is, lives entirely in exit selection, not entry timing.

User wants to move toward **discretionary options buying**: position
handling driven by underlying context (ranging vs trending bullish/bearish)
and options behavior, rather than one fixed ORB-only entry rule. Given (b)
above — ORB entries carry no measurable edge — testing exit strategies
against a *regime-driven* entry (instead of ORB-only) is the natural next
experiment: does the "only mfe_retrace_25 works" finding hold across
different market regimes, or does a different exit win in trending vs
ranging conditions?

This spec covers **Phase 1: analysis only** — generate regime-driven
signals, run them through the already-fixed `Pipeline`/`TradeScorer` path,
and report which exit strategy performs best *per regime bucket*. It does
**not** build a regime→strategy switching engine (Phase 2) — that depends on
what Phase 1's numbers actually show.

## Goals

- Generate `Research::Signal` rows from underlying regime state (trend +
  volatility for trending entries, liquidity-sweep for ranging entries)
  instead of only from the ORB `First15mEngine` lineage or manual input.
- Score those signals through the existing, already-fixed pipeline
  (`Research::Pipeline` → `Research::TradeScorer` → `exit_simulations`) with
  zero changes to that path.
- Produce a report ranking all 14 exit strategies' performance *within each
  regime bucket* (not one aggregate number across every trade), reusing the
  existing stats math (`Research::ResearchReportGenerator.evaluate_exits`)
  rather than recomputing win-rate/expectancy/Sharpe a third time.
- Ship as a rake task, matching the two existing research rake tasks'
  shape — no controller/dashboard work in this phase.

## Non-goals

- No regime→exit-strategy selection/switching logic (Phase 2, blocked on
  this phase's findings).
- No changes to `Research::Pipeline`, `Research::TradeScorer`,
  `Research::CandidateExitSimulator`, or `Research::ExitCaptureAnalyzer`.
- No live-trading wiring of any kind — this stays entirely inside
  `Research::`, per the project's stable/alpha layering policy.
- No continuous/per-minute regime scanner — checkpoint-based only (see
  Design decisions).

## Design

### 1. `Research::RegimeSignalGenerator` (new)

```ruby
Research::RegimeSignalGenerator.run(
  symbol:, from_date:, to_date:,
  checkpoint_times: ["09:45", "11:30", "13:30", "15:00"]
)
```

For each trading day in `[from_date, to_date]`, for each checkpoint time:

1. `Research::UnderlyingContextSnapshot.at(symbol:, timestamp:)` — fully
   reused, already returns `close` (spot) and `"regime"` (all
   `ContextClassifier` labels: `trend`, `volatility_regime`,
   `liquidity_sweep`, etc.). Returns `{}` on insufficient candle history —
   treated as "skip this checkpoint," not an error.
2. Direction decision (new logic, the only new decision logic in this
   spec):
   - `trend ∈ {strong_bullish, weak_bullish}` AND
     `volatility_regime == "expanding"` → `"bullish"`
   - `trend ∈ {strong_bearish, weak_bearish}` AND
     `volatility_regime == "expanding"` → `"bearish"`
   - `trend == "neutral"` (ranging) AND `liquidity_sweep == "sell_side_sweep"`
     → `"bullish"` (reversal up)
   - `trend == "neutral"` AND `liquidity_sweep == "buy_side_sweep"` →
     `"bearish"` (reversal down)
   - anything else (weak trend without expansion, ranging with no sweep,
     `{}` snapshot) → no signal, move to the next checkpoint
3. `Research::SignalSnapshotBuilder.build(underlying_symbol:, signal_timestamp:,
   direction:, spot_price:, strategy_name: "regime_scan", metadata: { "regime" => snapshot["regime"], "checkpoint" => label })`
   — fully reused. `metadata["regime"]` is what `RegimeExitReport` (below)
   groups by later.
4. Idempotency: `find_or_create_by(underlying_symbol:, signal_timestamp:,
   strategy_name: "regime_scan")` — re-running the same date range doesn't
   duplicate signals.
5. Per-checkpoint `rescue StandardError` — logs and continues, same
   per-item isolation already used in `Pipeline`/`LifecycleRunner` (one bad
   checkpoint doesn't kill the whole date-range scan).

Returns the array of created/found `Research::Signal` records.

### 2. Existing `Research::Pipeline.run(signal:, max_distance: 0)`

Called once per generated signal, unmodified. `max_distance: 0` → ATM only
(prior research showed strike offset barely moves outcomes — see Context).
This is what already produces `OptionCandidate` rows with `exit_simulations`
populated (from last session's fix).

### 3. `Research::RegimeExitReport` (new)

```ruby
Research::RegimeExitReport.call(
  scope: Research::OptionCandidate.where(status: "scored"),
  regime_dimensions: %w[trend volatility_regime liquidity_sweep]
)
```

Shaped like `Research::ExpectancyReport` (group-by-dimension, rank buckets)
but for exit-strategy comparison instead of lifecycle peak/end returns:

1. For each candidate in scope whose `research_signal.strategy_name ==
   "regime_scan"`: read `candidate.research_signal.metadata["regime"]`,
   build a context hash from the requested dimensions (unknown/missing dims
   → `"unknown"`, matching `ExpectancyReport`'s existing convention).
2. Group candidates by that context hash.
3. Per bucket: build a `trades`-shaped array —
   `bucket.map { |c| { strikes: { c.strike_label => { exits: c.exit_simulations.deep_symbolize_keys } } } }`
   — and call `Research::ResearchReportGenerator.evaluate_exits(trades,
   strike_label: "ATM")`. This is a straight reuse: `exit_simulations`
   already stores the exact field names (`return_pct`, `capture_efficiency`,
   `holding_time_minutes`, `opportunity_retention_ratio`,
   `lost_profit_points`) that `evaluate_exits` expects to `.dig` out, since
   both trace back to the same `ExitCaptureAnalyzer.run` output shape. No
   new stats math.
4. Within each bucket, sort strategies by `avg_return_pct` descending.
5. Return `{ buckets: [{ context:, sample_size:, strategies: {...ranked...} }], dimensions:, total_candidates: }`.

### 4. Rake task

`research:run_regime_scan[symbol,from_date,to_date]` in
`lib/tasks/research.rake`, matching the existing two tasks' shape:
runs `RegimeSignalGenerator.run` → `Research::Pipeline.run` per signal →
`RegimeExitReport.call` → prints a ranked table per regime bucket
(regime label / sample size / best strategy / its expectancy% / win%).

## Design decisions (alternatives considered)

**Checkpoint-based vs. continuous per-minute scanner.** Chose checkpoint
(4 fixed times/day, no state machine, no cooldown logic) over a continuous
scanner that would need to track "did the regime already trigger a signal
in this window" state. Checkpoint times are aligned to
`ContextClassifier`'s own `time_context` bucket boundaries, so the choice
piggybacks on an existing taxonomy instead of inventing new ones. A
continuous scanner is a plausible v2 if checkpoint-based results look
promising and finer entry timing turns out to matter — not built here.

**Hand-rolled stats vs. reusing `ResearchReportGenerator.evaluate_exits`.**
Chose reuse. The field-name match between `exit_simulations` and what
`evaluate_exits` already `.dig`s out is not a coincidence — both are
downstream of the same `ExitCaptureAnalyzer.run` return shape — so shaping
`RegimeExitReport`'s grouped candidates into the same `trades` hash and
calling the existing method is a direct fit, not a stretch. Avoids a third
independent implementation of win-rate/expectancy/Sharpe/profit-factor
(there are already two: `ResearchReportGenerator.evaluate_exits` and
`ExpectancyReport.summarize`).

**Ranging direction via `liquidity_sweep` vs. VWAP-deviation.** Chose the
already-computed `liquidity_sweep` label (SMC-based, `Smc::Detectors::Liquidity`)
over inventing a new VWAP-deviation-based mean-reversion rule, since the
project already reuses SMC's pure detectors for this exact purpose
elsewhere (`ContextClassifier` itself). No new detection logic needed.

## Testing

- `spec/services/research/regime_signal_generator_spec.rb`: direction
  decision table (stub `UnderlyingContextSnapshot.at` to return each
  regime combination, assert bullish/bearish/skip), idempotency
  (`find_or_create_by`), per-checkpoint failure isolation.
- `spec/services/research/regime_exit_report_spec.rb`: grouping by regime
  dimensions with fabricated `OptionCandidate`+`exit_simulations` fixtures,
  assert it delegates to `ResearchReportGenerator.evaluate_exits` and
  ranks by `avg_return_pct`.
- Manual: `rake research:run_regime_scan[NIFTY,2026-06-01,2026-07-01]`
  end-to-end against real DhanHQ data once credentials are available in
  the running environment (not available in this sandbox — noted as a
  known gap, same as last session).

## Open question carried to Phase 2

Once this report has real numbers: does the regime→best-exit mapping have
enough per-bucket sample size to trust (last full run's bootstrap CIs were
already borderline on 327 *un-regime-split* trades — splitting further
thins each bucket)? Phase 2 (build the actual regime-aware exit selector)
should not start until Phase 1's bucket sample sizes are checked.
