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

Initial exploration cast a wide net across ~22 spec files referencing a
broken namespace. Per-file verification (each file's failure signature
checked individually, not assumed from the aggregate) found that only a
subset share a common, mechanically-fixable root cause. The rest carry
their own distinct, unrelated bugs — some load-error-class typos, at least
one genuine exit-rule logic discrepancy (a `PRIORITY` constant mismatch).
Scope below reflects that per-file verification, not the initial broader
estimate.

1. **Wrong namespace, 22 spec files.** Tests reference
   `Positions::ActiveCache::PositionData`, but that class was deliberately
   moved out to `Positions::PositionData` (the code even carries a comment:
   "defined outside ActiveCache to avoid re-definition issues"). None of
   the 22 spec files were updated when that move happened. Fixing this one
   reference pattern alone — verified by testing it — took the 21-file core
   batch (excluding `rule_engine_simulation_spec.rb`) from 249 failures to
   75, and the full 22-file set from 249 to 102. Safe to apply across all
   22 regardless of what else each file needs — every file that references
   the wrong name gets it fixed, whether or not it has additional problems.

2. **`RuleContext` test setup gap — 3 spec files, cleanly verified.**
   `Risk::Rules::RuleContext` exposes both `position` (an object with
   delegated accessors: `pnl_pct`, `high_water_mark`, `peak_profit_pct`,
   `current_ltp`) and a separate `tracker_snapshot` (a raw Hash). Several
   production rule files read directly from `tracker_snapshot` (e.g.
   `trailing_stop_rule.rb`'s `snapshot[:pnl_pct]`). Confirmed via
   `unified_exit_checker.rb` (the real production caller) that
   `RuleContext.new` is always built with **both** `position:` and
   `tracker_snapshot:` together — this is the correct, intentional shape.
   Three spec files only ever pass `position:`, leaving `tracker_snapshot`
   `nil` and causing `undefined method '[]' for nil` the moment the rule
   under test runs, with **no other failure causes mixed in** (each file's
   failures are 100% this one pattern, verified per-file after the
   namespace fix): `trailing_stop_rule_spec.rb` (11 failures, 1
   `RuleContext.new` call), `take_profit_rule_spec.rb` (10 failures, 1
   call), `stop_loss_rule_spec.rb` (10 failures, 1 call). Confirmed as a
   **test gap, not a production bug**.

   **Explicitly not included here**, despite superficially similar
   `RuleContext.new`/`tracker_snapshot` references, because per-file
   verification found each has its own distinct, different-shaped problem
   mixed in — grouping them with the clean 3 would mean guessing at fixes
   for problems not yet actually characterized:
   - `time_based_exit_rule_spec.rb` — mostly genuine logic-level
     mismatches, not a nil-snapshot crash: `expect(result.exit?).to be
     true` returning `false`, and `expected: 40` (spec's expected
     `PRIORITY`) vs `got: 100` (actual). This is an exit-rule *logic*
     question — the kind of thing this spec's own non-goals rule out.
   - `data_freshness_spec.rb` — failures are assertion mismatches
     (`expected true`, `expected: 20.0`), not the nil-snapshot crash.
   - `underlying_exit_rule_spec.rb` — `uninitialized constant
     UnderlyingState`. A different missing-reference bug: the spec builds
     `instance_double(UnderlyingState, ...)`, but no `UnderlyingState`
     class exists anywhere in the codebase — production
     (`Live::UnderlyingMonitor#evaluate`) returns a plain `OpenStruct`,
     never a class by that name.
   - `edge_cases_spec.rb` — mixed failures including one entirely
     unrelated to this rule engine: a `MarketFeedHub`/WebSocket
     subscription mocking issue (`undefined method 'subscribe_one' for
     nil`) alongside rule-logic assertion mismatches.
   - `trailing_activation_spec.rb` — only 4 of 29 examples share the
     nil-snapshot pattern after the namespace fix (not all 8 `let(:context)`
     blocks originally suspected); the rest are unrelated.
   - `rule_engine_spec.rb`, `integration_scenarios_spec.rb` — not
     individually triaged; each needs the same per-file verification
     before any fix is assumed.

   These 7 files become their own follow-up investigation (each needs to
   be read on its own merits, not batched), not part of this phase.

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

### Finding 2: `tracker_snapshot:` gap (3 files)

For each of `trailing_stop_rule_spec.rb`, `take_profit_rule_spec.rb`,
`stop_loss_rule_spec.rb`: each has exactly one `RuleContext.new` call
(a single `let(:context)`). Add a `tracker_snapshot:` hash to that call
containing at minimum `pnl_pct:` (the only field the corresponding rule
reads — verified via `grep "snapshot\[" app/services/risk/rules/
<rule>.rb`), sourced from the same value already used to build
`position_data` in that file's `let` block, so the two stay consistent
with each other, matching what production code guarantees.

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
- After finding 1: re-run all 22 files, confirm the failure count drops
  from 249 to the sum of what's expected to remain (finding 2's 3 files
  fixed by finding 2, `rule_engine_simulation_spec.rb`'s 27 by finding 3,
  the 7 parked files' failures unchanged since finding 1 alone doesn't
  resolve them).
- After finding 2: confirm `trailing_stop_rule_spec.rb`,
  `take_profit_rule_spec.rb`, `stop_loss_rule_spec.rb` are each fully
  green (0 failures).
- After finding 3: confirm `rule_engine_simulation_spec.rb`'s 27 examples
  pass.
- Final: run all 22 files together. Expected result: the 4 files from
  findings 2+3 are green; the other ~18 (namespace-only fix, or one of the
  7 parked files) show only their pre-existing, out-of-scope failures —
  confirm none of those counts *increased* from this phase's changes.

## Handoff

The 7 parked files from finding 2 (`time_based_exit_rule_spec.rb`,
`data_freshness_spec.rb`, `underlying_exit_rule_spec.rb`,
`edge_cases_spec.rb`, `trailing_activation_spec.rb`,
`rule_engine_spec.rb`, `integration_scenarios_spec.rb`), Phase B (exit-rule
*logic* audit using the now-more-trustworthy test suite), and the parked
`risk_manager_service_spec.rb` triage all become their own follow-up
sub-projects once this phase lands.
