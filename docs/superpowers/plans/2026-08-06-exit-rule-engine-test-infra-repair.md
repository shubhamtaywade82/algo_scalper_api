# Exit-Rule-Engine Test Infrastructure Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get 4 exit-rule-engine spec files (plus 21 others sharing one of their bugs) actually running, by fixing 3 confirmed test-infrastructure gaps — none of which are production code bugs.

**Architecture:** Spec-only changes. No production code is modified — every finding in this plan was confirmed (by testing the fix, then reverting, before this plan was written) to be a test-side gap against correct, unchanged production behavior.

**Tech Stack:** Ruby 3.3.4, Rails 8 API-only, RSpec, FactoryBot.

## Global Constraints

- No production code changes. If executing a task reveals a production bug, stop and flag it — don't fix it inline, it's out of this plan's scope (see the design spec's non-goals).
- The 7 files explicitly parked in the design spec (`time_based_exit_rule_spec.rb`, `data_freshness_spec.rb`, `underlying_exit_rule_spec.rb`, `edge_cases_spec.rb`, `trailing_activation_spec.rb`, `rule_engine_spec.rb`, `integration_scenarios_spec.rb`) get the namespace fix (Task 1, since they share that one bug) but nothing else — don't attempt to fix their other failures.
- `risk_manager_service_spec.rb` is not touched at all in this plan.

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

## Task 3: `rule_engine_simulation_spec.rb` helper rewrite

**Files:**
- Modify: `spec/services/risk/rule_engine_simulation_spec.rb`

**Interfaces:**
- Consumes: `Positions::ActiveCache#add_position(tracker:, sl_price: nil, tp_price: nil)` (existing, real signature — creates a `PositionData` with `pnl`/`pnl_pct`/`current_ltp` all zeroed, since production expects those to arrive later via tick/PnL events) and `Positions::ActiveCache#update_position(tracker_id, **updates)` (existing — the established way production code updates fields on an already-cached position after creation).
- Produces: `create_position_in_cache(pnl:, pnl_pct:, ltp:, hwm_pnl: nil, peak_profit_pct: nil)` keeps the exact same call signature every other part of this file already uses — only its internals change.

- [ ] **Step 1: Fix the hardcoded invalid segment**

In `spec/services/risk/rule_engine_simulation_spec.rb`, change:
```ruby
      segment: 'FUTSTK',
```
to:
```ruby
      segment: 'NSE_FNO',
```
(in the `let(:tracker)` block's `create(:position_tracker, ...)` call —
`FUTSTK` isn't in `PositionTracker`'s valid-segment list; `NSE_FNO` matches
the `:nifty_future` instrument type already used by this file's
`let(:instrument)`.)

- [ ] **Step 2: Rewrite `create_position_in_cache`**

Change:
```ruby
  # Helper to create/update position in ActiveCache
  def create_position_in_cache(pnl:, pnl_pct:, ltp:, hwm_pnl: nil, peak_profit_pct: nil)
    position_data = Positions::ActiveCache::PositionData.new(
      tracker_id: tracker.id,
      security_id: tracker.security_id,
      segment: tracker.segment,
      entry_price: tracker.entry_price,
      quantity: tracker.quantity,
      current_ltp: ltp,
      pnl: pnl,
      pnl_pct: pnl_pct,
      high_water_mark: hwm_pnl || pnl,
      peak_profit_pct: peak_profit_pct || pnl_pct,
      last_updated_at: Time.current
    )
    active_cache.add_position(position_data)
    position_data
  end
```
to:
```ruby
  # Helper to create/update position in ActiveCache
  def create_position_in_cache(pnl:, pnl_pct:, ltp:, hwm_pnl: nil, peak_profit_pct: nil)
    active_cache.add_position(tracker: tracker)
    active_cache.update_position(
      tracker.id,
      current_ltp: ltp,
      pnl: pnl,
      pnl_pct: pnl_pct,
      high_water_mark: hwm_pnl || pnl,
      peak_profit_pct: peak_profit_pct || pnl_pct
    )
    active_cache.get_by_tracker_id(tracker.id)
  end
```

This matches the real `ActiveCache` API: `add_position(tracker:)` creates
the entry (internally building its own `PositionData` from the tracker,
with PnL fields zeroed), then `update_position` — the same method
production code uses to apply tick/PnL updates after creation — sets the
test's specific PnL/LTP/HWM values.

- [ ] **Step 3: Run it to verify it passes**

Run: `bundle exec rspec spec/services/risk/rule_engine_simulation_spec.rb`
Expected: PASS, 0 failures (was 27). If any examples still fail, read the
specific failure — `add_position` returns `nil` if `tracker.active?` is
false or `tracker.entry_price` isn't positive (see
`app/services/positions/active_cache.rb:182-184`), so a failure here most
likely means the `tracker` factory build in this file needs a matching
adjustment, not a further rewrite of this helper.

- [ ] **Step 4: Commit**

```bash
git add spec/services/risk/rule_engine_simulation_spec.rb
git commit -m "Fix rule_engine_simulation_spec.rb's ActiveCache API mismatch

create_position_in_cache hand-built a PositionData and passed it
positionally to add_position - but the real signature is
add_position(tracker:, sl_price:, tp_price:), which builds its own
PositionData internally with PnL fields zeroed (populated later via
tick events in production). Rewrote to call add_position(tracker:)
then update_position(tracker.id, **pnl_fields) - the same two-step
flow production code uses. Also fixed a hardcoded segment: 'FUTSTK',
which isn't a valid PositionTracker segment, to 'NSE_FNO' matching
the :nifty_future instrument already used here."
```

---

## Final Verification

- [ ] **Step 1: Run all 22 files from Task 1's list together**

Run: `bundle exec rspec spec/integration/exit_rules_spec.rb spec/services/risk/rules/secure_profit_rule_spec.rb spec/services/risk/rules/stop_loss_rule_spec.rb spec/services/risk/rules/underlying_exit_rule_spec.rb spec/services/risk/rules/rule_engine_spec.rb spec/services/risk/rules/trailing_stop_rule_spec.rb spec/services/risk/rules/session_end_rule_spec.rb spec/services/risk/rule_engine_simulation_spec.rb spec/services/risk/rules/peak_drawdown_rule_spec.rb spec/services/risk/rules/time_based_exit_rule_spec.rb spec/services/risk/rules/edge_cases_spec.rb spec/services/risk/rules/rule_context_spec.rb spec/services/risk/rules/trailing_activation_spec.rb spec/services/live/risk_manager_underlying_spec.rb spec/services/live/underlying_monitor_spec.rb spec/services/live/trailing_engine_spec.rb spec/services/live/risk_manager_service_spec.rb spec/services/orders/bracket_placer_spec.rb spec/services/orders/entry_manager_spec.rb spec/services/risk/rules/data_freshness_spec.rb spec/services/risk/rules/bracket_limit_rule_spec.rb spec/services/risk/rules/take_profit_rule_spec.rb spec/services/risk/rules/integration_scenarios_spec.rb`

Expected: `trailing_stop_rule_spec.rb`, `take_profit_rule_spec.rb`,
`stop_loss_rule_spec.rb`, and `rule_engine_simulation_spec.rb` all fully
green. The other 18 files show only their pre-existing failures (the 7
parked files' distinct bugs, `risk_manager_service_spec.rb`'s 133, and
whatever the remaining namespace-only files' baseline is) — confirm the
total failure count for those 18 hasn't *increased* from before this plan
started (it should only have decreased, by the namespace fix alone, same
as measured during the design/brainstorming phase).

- [ ] **Step 2: RuboCop on every touched file**

Run: `bundle exec rubocop spec/services/risk/rules/trailing_stop_rule_spec.rb spec/services/risk/rules/take_profit_rule_spec.rb spec/services/risk/rules/stop_loss_rule_spec.rb spec/services/risk/rule_engine_simulation_spec.rb`

Expected: no new offenses on the lines this plan changed. (The other 18
files touched only by Task 1's mechanical sed aren't re-linted here since
that fix is a pure string substitution with no risk of introducing a style
violation.)

- [ ] **Step 3: Confirm no stray debug output**

Run: `grep -rn "binding.pry\|byebug" spec/services/risk/rules/trailing_stop_rule_spec.rb spec/services/risk/rules/take_profit_rule_spec.rb spec/services/risk/rules/stop_loss_rule_spec.rb spec/services/risk/rule_engine_simulation_spec.rb`

Expected: no output.
