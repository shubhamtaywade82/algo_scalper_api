# Exit-rule-engine test infrastructure repair

Date: 2026-08-06

## Context

Sub-project 3 of 6 (backend services audit) started with a full spec sweep
across `spec/services/signal/`, `spec/services/entries/`,
`spec/services/risk/`, `spec/services/capital/`, and `spec/services/options/`.
`spec/services/risk/` alone showed 234 of 307 examples failing.

Investigation (each hypothesis tested directly, then reverted, before being
accepted) found the dominant cause is not scattered logic bugs but **broken
test infrastructure** blocking the exit-rule-engine suite — the code that
decides when a live position gets closed (stop-loss, take-profit, trailing,
secure-profit, peak-drawdown, time/session exits) — from running at all.
Per CLAUDE.md, this is one of the most safety-critical parts of the system,
and right now essentially none of it is under verified test coverage.

This spec covers **Phase A only: get the suite running.** No exit-rule
*logic* changes are in scope — that's Phase B, a separate sub-project once
these tests can actually validate something.

## Findings (each verified by testing the fix, then reverting before writing this spec)

1. **Wrong namespace, 22 spec files.** Tests reference
   `Positions::ActiveCache::PositionData`, but that class was deliberately
   moved out to `Positions::PositionData` (the code even carries a comment:
   "defined outside ActiveCache to avoid re-definition issues"). None of
   the 22 spec files were updated when that move happened. Fixing this one
   reference pattern alone — verified by testing it — took the 21-file core
   batch (excluding the two files below) from 249 failures to 75, and the
   full 22-file set from 249 to 102.

2. **`RuleContext` test setup gap, ~10 spec files, ~50 call sites.**
   `Risk::Rules::RuleContext` exposes both `position` (an object with
   delegated accessors: `pnl_pct`, `high_water_mark`, `peak_profit_pct`,
   `current_ltp`) and a separate `tracker_snapshot` (a raw Hash). 11
   production rule files (`trailing_stop_rule.rb`, `take_profit_rule.rb`,
   `stop_loss_rule.rb`, `structure_invalidation_rule.rb`,
   `early_trend_failure_rule.rb`, `green_trade_cap_rule.rb`,
   `percentage_pnl_rule.rb`, `adaptive_trail_rule.rb`,
   `smc_navigator_rule.rb`, `profit_floor_exit_rule.rb`, and
   `rule_context.rb` itself) read directly from `tracker_snapshot` (e.g.
   `snapshot[:pnl_pct]`). Confirmed via `unified_exit_checker.rb` (the real
   production caller) that `RuleContext.new` is always built with **both**
   `position:` and `tracker_snapshot:` together — this is the correct,
   intentional shape. The affected spec files only ever pass `position:`,
   leaving `tracker_snapshot` `nil` and causing `undefined method '[]' for
   nil` the moment an affected rule runs. Confirmed as a **test gap, not a
   production bug** — no production code path is missing `tracker_snapshot`.
   Affected files (verified via `RuleContext.new` call count, 0
   `tracker_snapshot:` occurrences in each): `trailing_stop_rule_spec.rb`
   (1 call), `take_profit_rule_spec.rb` (1), `stop_loss_rule_spec.rb` (1),
   `time_based_exit_rule_spec.rb` (3), `data_freshness_spec.rb` (4),
   `underlying_exit_rule_spec.rb` (1), `trailing_activation_spec.rb` (8,
   independent `let(:context)` blocks across separate `describe`/`context`
   groups — not a shared helper), `edge_cases_spec.rb` (8),
   `rule_engine_spec.rb` (1), `integration_scenarios_spec.rb` (14).
   `rule_context_spec.rb` has 0 `RuleContext.new` calls of this shape and
   isn't affected the same way — check during implementation whether it
   needs anything.

3. **`rule_engine_simulation_spec.rb`'s core helper is structurally wrong,
   1 file, ~27 tests.** `create_position_in_cache` builds a `PositionData`
   object by hand and calls `active_cache.add_position(position_data)` — a
   single positional argument. The real signature is `add_position(tracker:,
   sl_price: nil, tp_price: nil)`, which builds its own internal
   `PositionData` **from the tracker**, not from a pre-built object handed
   in. On top of the namespace bug (finding 1), this file also hardcodes
   `segment: 'FUTSTK'` on its `PositionTracker` factory call, which fails a
   real model validation (`PositionTracker` only accepts `NSE_EQ/NSE_FNO/
   NSE_CURRENCY/BSE_EQ/BSE_FNO/BSE_CURRENCY/MCX_COMM` — confirmed via the
   same `VALID_TRADABLE_SEGMENTS` list used in `Orders::Placer`). Fixing
   findings 1 and the segment alone still leaves all 27 examples failing on
   the `add_position` signature mismatch — this file needs its helper
   rewritten to either mock `Live::RedisPnlCache`/`TickCache` ahead of
   calling `add_position(tracker: tracker)` (letting `ActiveCache` derive
   PnL internally, matching production usage), or call whatever lower-level
   API the tests actually need to drive PnL/LTP values directly. Exact
   approach gets pinned during the implementation plan after reading
   `ActiveCache#add_position` and its PnL-sourcing path in full.

## Non-goals

- No changes to exit-rule *logic* — `trailing_stop_rule.rb`,
  `take_profit_rule.rb`, and the other 13 exit rule engines are not
  modified, only the tests that exercise them.
- No changes to `RuleContext`, `ActiveCache#add_position`, or any other
  production code — every fix in this phase is spec-only, since all three
  findings were confirmed as test-side gaps against correct, unchanged
  production behavior.
- **`risk_manager_service_spec.rb` (133 failures) is explicitly parked**,
  not part of this phase. Initial read suggested `RiskManagerService` might
  be a stripped-down shell missing most of its spec's expected
  functionality — that read was wrong (the class `include`s 5 substantial
  submodules totaling ~1925 lines, not 214). But several specific methods
  the spec expects (`increment_metric`, `feature_flags`,
  `stagger_api_calls`, `loop_sleep_interval`,
  `MAX_RETRIES_ON_RATE_LIMIT`) are genuinely absent across the base class
  and all 5 submodules. Untangling which of the 133 failures are real gaps
  versus stale/aspirational spec content needs dedicated, careful
  triage — not something to rush through inside this phase given how
  safety-critical this service is (PnL guard, daily limits, kill switch).
- No changes to the 4 unrelated pre-existing failures already confirmed
  out of scope earlier this session (`entry_guard_pipeline` method-name
  mismatch, `banknifty_last_week?` visibility, `LossStreakGuard` missing
  from pipeline, `segment_expectancy_guard_spec.rb`'s load error) — those
  belong to entry-pipeline work, not the exit-rule-engine suite.

## Design

### Finding 1: namespace fix

Global find-replace `Positions::ActiveCache::PositionData` →
`Positions::PositionData` across all 22 affected files (the 21 in finding
2's list plus `rule_engine_simulation_spec.rb`). Mechanical, already
verified safe.

### Finding 2: `tracker_snapshot:` gap

For each of the ~10 affected files: read the rule(s) under test in that
file to see exactly which `tracker_snapshot` keys they read (e.g.
`trailing_stop_rule.rb` reads `snapshot[:pnl_pct]`), then add a
`tracker_snapshot:` hash to each `RuleContext.new` call in that file with
those keys populated from the same values already used to build
`position_data` in that `let` block (so the two stay consistent with each
other, matching what production code guarantees). This is a repeated
pattern across ~50 call sites, not a single edit — the implementation plan
works through each file, verifies red→green per file, and does not attempt
one global mechanical transform (each rule reads a different subset of
snapshot keys, so a blanket auto-generated hash would either be wrong for
some rules or need to over-include fields no test asserts on).

### Finding 3: `rule_engine_simulation_spec.rb` helper rewrite

Read `Positions::ActiveCache#add_position` and how it sources PnL/LTP data
internally (likely via `Live::RedisPnlCache` or `Live::TickCache`, since
`ActiveCache` is documented elsewhere in this codebase as syncing from
Redis). Rewrite `create_position_in_cache` to either mock that data source
before calling `active_cache.add_position(tracker: tracker, ...)`, or find
whichever API surface actually lets a test set PnL/LTP directly if one
exists. Also fix `segment: 'FUTSTK'` → `segment: 'NSE_FNO'` on this file's
`PositionTracker` factory call (matching the `:nifty_future` instrument
type already used).

## Testing

This phase's own deliverable *is* test fixes — "testing" here means
verifying each fix actually turns red to green without introducing new
failures:
- After finding 1: re-run the 21-file core batch, confirm 249→~102
  failures (already verified once, re-verify after the real commit).
- After finding 2, per file: confirm that specific file goes fully green
  (or down to only findings-3/1-related failures if the file also touches
  `rule_engine_simulation_spec.rb`'s helper, which it doesn't — these are
  disjoint file sets).
- After finding 3: confirm `rule_engine_simulation_spec.rb`'s 27 examples
  pass.
- Final: full run across all 22 files, confirm 0 failures (or document any
  residual failure as a genuine, separate finding — not silently left
  red).

## Handoff

Phase B (exit-rule *logic* audit, using the now-working test suite to find
real bugs in the 15 exit rule engines) and the parked
`risk_manager_service_spec.rb` triage both become their own follow-up
sub-projects once this phase lands.
