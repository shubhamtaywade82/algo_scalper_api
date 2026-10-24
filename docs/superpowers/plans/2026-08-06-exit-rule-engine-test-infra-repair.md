# Exit-Rule-Engine Test Infrastructure Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get 3 exit-rule-engine spec files (plus 20 others sharing their namespace bug) actually running, by fixing confirmed test-infrastructure gaps.

**Outcome as executed:** Tasks 1 and 2 completed and verified (23 files namespace-fixed; `trailing_stop_rule_spec.rb`, `take_profit_rule_spec.rb`, `stop_loss_rule_spec.rb` fully passing against their real production dependencies). Task 3 was investigated and deferred — see its section below — after discovering its target file's core premise doesn't match production's actual architecture, which is a bigger, separate investigation.

**Architecture:** Spec-only changes, with one narrow, explicitly-approved exception: `app/services/risk/rules/take_profit_rule.rb` had dead code left over from a prior refactor that raised `NameError` on every evaluation where take-profit wasn't hit (masked in production by `RuleEngine`'s per-rule rescue, but meant this rule never contributed a real result and spammed error logs every tick). Fixed inline with explicit user approval — see Task 2.

**Tech Stack:** Ruby 3.3.4, Rails 8 API-only, RSpec, FactoryBot.

## Global Constraints

- No production code changes except the one explicitly-approved exception in Task 2 (`take_profit_rule.rb`'s dead-code bug). Any other production bug found during execution: stop and flag it, don't fix it inline.
- The 7 files explicitly parked in the design spec (`time_based_exit_rule_spec.rb`, `data_freshness_spec.rb`, `underlying_exit_rule_spec.rb`, `edge_cases_spec.rb`, `trailing_activation_spec.rb`, `rule_engine_spec.rb`, `integration_scenarios_spec.rb`) get the namespace fix (Task 1, since they share that one bug) but nothing else.
- `risk_manager_service_spec.rb` is not touched at all in this plan.
- `rule_engine_simulation_spec.rb` gets Task 1's namespace fix only — Task 3 (everything else it needs) is deferred, not attempted.

---

## Task 1: Namespace fix across all 22 files

**Files:**
- Modify: all 22 files listed below (mechanical find-replace, same change in each)

**Interfaces:** None — this changes a class reference in test code only, no production interface involved.

- [ ] **Step 1: Confirm the full file list**

Run: `grep -rl "Positions::ActiveCache::PositionData" spec/ --include="*.rb"`
Expected output (22 files):
```
spec/integration/exit_rules_spec.rb
spec/services/risk/rules/secure_profit_rule_spec.rb
spec/services/risk/rules/stop_loss_rule_spec.rb
spec/services/risk/rules/underlying_exit_rule_spec.rb
spec/services/risk/rules/rule_engine_spec.rb
spec/services/risk/rules/trailing_stop_rule_spec.rb
spec/services/risk/rules/session_end_rule_spec.rb
spec/services/risk/rule_engine_simulation_spec.rb
spec/services/risk/rules/peak_drawdown_rule_spec.rb
spec/services/risk/rules/time_based_exit_rule_spec.rb
spec/services/risk/rules/edge_cases_spec.rb
spec/services/risk/rules/rule_context_spec.rb
spec/services/risk/rules/trailing_activation_spec.rb
spec/services/live/risk_manager_underlying_spec.rb
spec/services/live/underlying_monitor_spec.rb
spec/services/live/trailing_engine_spec.rb
spec/services/live/risk_manager_service_spec.rb
spec/services/orders/bracket_placer_spec.rb
spec/services/orders/entry_manager_spec.rb
spec/services/risk/rules/data_freshness_spec.rb
spec/services/risk/rules/bracket_limit_rule_spec.rb
spec/services/risk/rules/take_profit_rule_spec.rb
spec/services/risk/rules/integration_scenarios_spec.rb
```
If the list differs, use the actual output for Step 2 instead of the list above (something may have changed since this plan was written).

- [ ] **Step 2: Apply the fix**

Run:
```bash
grep -rl "Positions::ActiveCache::PositionData" spec/ --include="*.rb" | \
  xargs sed -i 's/Positions::ActiveCache::PositionData/Positions::PositionData/g'
```

- [ ] **Step 3: Verify the fix landed correctly**

Run: `grep -rl "Positions::ActiveCache::PositionData" spec/ --include="*.rb"`
Expected: no output (zero remaining references).

Run: `grep -c "Positions::PositionData" spec/services/risk/rules/trailing_stop_rule_spec.rb`
Expected: `1` (confirms the replacement produced valid, findable references).

- [ ] **Step 4: Run the 3 files Task 2 will fix, to confirm this step alone doesn't already fix them (it shouldn't — they need Task 2 too) and to get a clean baseline**

Run: `bundle exec rspec spec/services/risk/rules/trailing_stop_rule_spec.rb spec/services/risk/rules/take_profit_rule_spec.rb spec/services/risk/rules/stop_loss_rule_spec.rb 2>&1 | tail -15`
Expected: still failing (11 + 10 + 10 = 31 failures), all `NoMethodError: undefined method '[]' for nil` — confirms the namespace fix alone isn't sufficient for these 3, setting up Task 2's starting point correctly.

- [ ] **Step 5: Run `risk_manager_service_spec.rb` to confirm it's explicitly untouched by this task's intent (parked, not in scope)**

No action needed — just don't run a "must improve" check against it. It's excluded per Global Constraints.

- [ ] **Step 6: Commit**

```bash
git add spec/integration/exit_rules_spec.rb \
  spec/services/risk/rules/secure_profit_rule_spec.rb \
  spec/services/risk/rules/stop_loss_rule_spec.rb \
  spec/services/risk/rules/underlying_exit_rule_spec.rb \
  spec/services/risk/rules/rule_engine_spec.rb \
  spec/services/risk/rules/trailing_stop_rule_spec.rb \
  spec/services/risk/rules/session_end_rule_spec.rb \
  spec/services/risk/rule_engine_simulation_spec.rb \
  spec/services/risk/rules/peak_drawdown_rule_spec.rb \
  spec/services/risk/rules/time_based_exit_rule_spec.rb \
  spec/services/risk/rules/edge_cases_spec.rb \
  spec/services/risk/rules/rule_context_spec.rb \
  spec/services/risk/rules/trailing_activation_spec.rb \
  spec/services/live/risk_manager_underlying_spec.rb \
  spec/services/live/underlying_monitor_spec.rb \
  spec/services/live/trailing_engine_spec.rb \
  spec/services/live/risk_manager_service_spec.rb \
  spec/services/orders/bracket_placer_spec.rb \
  spec/services/orders/entry_manager_spec.rb \
  spec/services/risk/rules/data_freshness_spec.rb \
  spec/services/risk/rules/bracket_limit_rule_spec.rb \
  spec/services/risk/rules/take_profit_rule_spec.rb \
  spec/services/risk/rules/integration_scenarios_spec.rb
git commit -m "Fix PositionData namespace reference across 22 spec files

Positions::PositionData was deliberately moved out of Positions::
ActiveCache (the code carries a comment explaining why - avoiding
re-definition issues) but no spec was updated when that happened.
Verified by testing: this one reference fix alone takes the affected
files from 249 failures to 102, with no production code touched."
```

---

## Task 2: `tracker_snapshot:` gap — 3 files

**Files:**
- Modify: `spec/services/risk/rules/trailing_stop_rule_spec.rb`
- Modify: `spec/services/risk/rules/take_profit_rule_spec.rb`
- Modify: `spec/services/risk/rules/stop_loss_rule_spec.rb`

**Interfaces:**
- Consumes: `Risk::Rules::RuleContext.new(position:, tracker:, risk_config:, tracker_snapshot: nil)` — existing keyword, currently omitted by all 3 files.
- Produces: no interface change — same `context` object shape, just fully populated instead of partially.

All 3 files share the identical structure: one `let(:position_data)` block
building a `Positions::PositionData`, and one `let(:context)` block calling
`Risk::Rules::RuleContext.new(position: position_data, tracker: tracker,
risk_config: risk_config)`. Each file's rule under test reads only
`snapshot[:pnl_pct]` from `tracker_snapshot` (confirmed via `grep
"snapshot\[" app/services/risk/rules/<rule>.rb` for all three: only
`pnl_pct` appears). Fix: add `tracker_snapshot: { pnl_pct:
position_data.pnl_pct }` to each `context` block, referencing
`position_data.pnl_pct` (not a hardcoded number) so it stays correct when
individual examples override `position_data.pnl_pct` via a `before` block
(as `trailing_stop_rule_spec.rb` already does in one context).

- [ ] **Step 1: Fix `trailing_stop_rule_spec.rb`**

Change:
```ruby
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config
    )
  end
```
to:
```ruby
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config,
      tracker_snapshot: { pnl_pct: position_data.pnl_pct }
    )
  end
```

- [ ] **Step 2: Run it to verify it passes**

Run: `bundle exec rspec spec/services/risk/rules/trailing_stop_rule_spec.rb`
Expected: PASS, 0 failures (was 11).

- [ ] **Step 3: Fix `take_profit_rule_spec.rb`**

Same change as Step 1, applied to this file's identically-structured
`let(:context)` block.

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/services/risk/rules/take_profit_rule_spec.rb`
Expected: PASS, 0 failures (was 10).

- [ ] **Step 5: Fix `stop_loss_rule_spec.rb`**

Same change as Step 1, applied to this file's identically-structured
`let(:context)` block.

- [ ] **Step 6: Run it to verify it passes**

Run: `bundle exec rspec spec/services/risk/rules/stop_loss_rule_spec.rb`
Expected: PASS, 0 failures (was 10).

- [ ] **Step 7: Run all 3 together**

Run: `bundle exec rspec spec/services/risk/rules/trailing_stop_rule_spec.rb spec/services/risk/rules/take_profit_rule_spec.rb spec/services/risk/rules/stop_loss_rule_spec.rb`
Expected: PASS, 0 failures, 33 examples (13 + 12 + 12, per the file header counts — Task 1's baseline check saw 11/10/10 *failures* out of these larger example counts).

- [ ] **Step 8: Commit**

```bash
git add spec/services/risk/rules/trailing_stop_rule_spec.rb spec/services/risk/rules/take_profit_rule_spec.rb spec/services/risk/rules/stop_loss_rule_spec.rb
git commit -m "Add missing tracker_snapshot: to RuleContext in 3 rule specs

TrailingStopRule, TakeProfitRule, and StopLossRule all read
tracker_snapshot[:pnl_pct] directly, but these 3 specs only ever
passed position: to RuleContext.new, leaving tracker_snapshot nil.
Confirmed via unified_exit_checker.rb (the real production caller)
that RuleContext is always built with both position: and
tracker_snapshot: together - this was a test gap, not a production
bug. Sourced pnl_pct from position_data.pnl_pct rather than
hardcoding it, so per-example overrides via before blocks stay
correct."
```

---

## Task 3: DEFERRED — `rule_engine_simulation_spec.rb` needs its own investigation, not a helper rewrite

**Status: not attempted.** Investigation while starting this task found the
file's core premise doesn't match production architecture, well beyond
what a helper-method rewrite can fix:

- `process_position`, the helper nearly all 27 examples call through,
  invokes `risk_manager.send(:check_exit_conditions_with_rule_engine, ...)`.
  **This method does not exist anywhere in the codebase** — not in
  `risk_manager_service.rb`, not in any of its 5 included submodules
  (`runner.rb`, `exit_enforcement.rb`, `exit_execution.rb`, `pnl_cache.rb`,
  `config.rb`).
- Production's real enforcement (`app/services/live/risk_manager_service/
  exit_enforcement.rb`) has no single unified "evaluate this position
  through the rule engine" entry point at all. It's ~15 separate,
  independently-named methods — `enforce_hard_limits_for`,
  `enforce_trailing_stops`/`enforce_dynamic_trailing_stops_for`,
  `enforce_structure_invalidation_for`, `enforce_premium_momentum_failure_for`,
  `enforce_time_stop_for`, `enforce_rr_profit_booking_for`,
  `enforce_percentage_pnl_exit_for`, `enforce_profit_floor_for`,
  `enforce_premium_r_stop_for`, `enforce_time_based_exit_for`, and others —
  each called separately, each presumably checking a different subset of
  rules.
- The real entry point closest to what this test wants is
  `Live::UnifiedExitChecker.check_exit_conditions(tracker)` (confirmed via
  `exit_enforcement.rb:26`, which calls it directly) — but its signature
  (`tracker` only, no `exit_engine`/`position_data` params) and return
  shape don't match what `process_position` assumes either.
- Confirmed via `grep`: `Risk::Rules::RuleEngine`/`RuleFactory` (the
  classes Task 2's 3 rules delegate into via `UnifiedExitChecker`) are
  referenced from exactly one file outside the `Risk::Rules::` namespace
  itself — `unified_exit_checker.rb`. So the rule classes fixed in Task 2
  *are* reachable from production, just through a much more indirect path
  (`enforce_*_for` → `UnifiedExitChecker` → sometimes `RuleEngine`) than
  this file's single-call-through-`RiskManagerService` premise assumes.

Properly fixing this file means understanding and correctly wiring against
that real, fragmented ~15-method architecture — which scenario in this
file's `describe` blocks maps to which `enforce_*_for` method, and whether
some scenarios (e.g. "Stop Loss Exit", "Take Profit Exit") have no direct
production entry point left to test against at all if their logic now only
runs through `UnifiedExitChecker.check_exit_conditions`. That's a
dedicated investigation — its own spec + plan cycle — not something to
improvise inside this one.

**What Task 1 already did for this file, and stays done:** the namespace
fix (`Positions::ActiveCache::PositionData` → `Positions::PositionData`)
was applied to this file along with the other 22 in Task 1's mechanical
pass. It's still correct and doesn't need reverting — it just isn't
sufficient on its own, and nothing further was attempted here.

---

## Final Verification

**Task 3 deferred (see above) — this verification covers Tasks 1 and 2 only.**

- [ ] **Step 1: Run the 20 files not explicitly parked or deferred**

Run: `bundle exec rspec spec/integration/exit_rules_spec.rb spec/services/risk/rules/secure_profit_rule_spec.rb spec/services/risk/rules/stop_loss_rule_spec.rb spec/services/risk/rules/underlying_exit_rule_spec.rb spec/services/risk/rules/rule_engine_spec.rb spec/services/risk/rules/trailing_stop_rule_spec.rb spec/services/risk/rules/session_end_rule_spec.rb spec/services/risk/rules/peak_drawdown_rule_spec.rb spec/services/risk/rules/time_based_exit_rule_spec.rb spec/services/risk/rules/edge_cases_spec.rb spec/services/risk/rules/rule_context_spec.rb spec/services/risk/rules/trailing_activation_spec.rb spec/services/live/risk_manager_underlying_spec.rb spec/services/live/underlying_monitor_spec.rb spec/services/live/trailing_engine_spec.rb spec/services/orders/bracket_placer_spec.rb spec/services/orders/entry_manager_spec.rb spec/services/risk/rules/data_freshness_spec.rb spec/services/risk/rules/bracket_limit_rule_spec.rb spec/services/risk/rules/take_profit_rule_spec.rb spec/services/risk/rules/integration_scenarios_spec.rb`

Expected (verified when this plan was executed): 246 examples, 44
failures — `trailing_stop_rule_spec.rb`, `take_profit_rule_spec.rb`, and
`stop_loss_rule_spec.rb` fully green; the other 17 files' 44 failures are
the 7 parked files' pre-existing, distinct bugs (unrelated to this plan —
see the design spec's non-goals). 44 is exactly the expected count: 75
(post-Task-1 baseline for this file set) minus 31 (the 3 files' combined
pre-Task-2 failures) = 44. If the count differs, something regressed —
investigate before considering this plan complete.

- [ ] **Step 2: RuboCop on every touched file**

Run: `bundle exec rubocop spec/services/risk/rules/trailing_stop_rule_spec.rb spec/services/risk/rules/take_profit_rule_spec.rb spec/services/risk/rules/stop_loss_rule_spec.rb app/services/risk/rules/take_profit_rule.rb`

Expected: no new offenses on the lines this plan changed. (The other 18
files touched only by Task 1's mechanical sed aren't re-linted here since
that fix is a pure string substitution with no risk of introducing a style
violation.)

- [ ] **Step 3: Confirm no stray debug output**

Run: `grep -rn "binding.pry\|byebug" spec/services/risk/rules/trailing_stop_rule_spec.rb spec/services/risk/rules/take_profit_rule_spec.rb spec/services/risk/rules/stop_loss_rule_spec.rb app/services/risk/rules/take_profit_rule.rb`

Expected: no output.
