# Signal Entry Outcome Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record whether a trading signal resulted in an entered position, a blocked entry (with the guard reason), or a skipped entry (pre-conditions not met), and display a compact badge in the Signals dashboard table.

**Architecture:** Two keys (`entry_outcome`, `entry_blocked_reason`) are written into the existing `metadata` jsonb column on `TradingSignal` — no migration needed. `Signal::Engine` records skips at four early-return points. `EntryGuard.try_enter` records blocked/entered outcomes. `BosEntryEngine` threads the signal through its private call chain. The Vue component reads `metadata.entry_outcome` for badge rendering.

**Tech Stack:** Ruby 3.3.4 / Rails 8, RSpec, Vue 3, Tailwind CSS.

---

## File Map

| File | Change |
|---|---|
| `app/models/trading_signal.rb` | Add `record_entry_outcome(outcome, reason)` instance method |
| `spec/models/trading_signal_spec.rb` | New file — unit tests for `record_entry_outcome` |
| `app/services/signal/engine.rb` | Capture signal from `create_from_analysis`; record skips at 4 post-creation early returns; pass `signal:` into `EntryGuard.try_enter` and `BosEntryEngine.run_for` |
| `app/services/entries/entry_guard.rb` | Add `signal: nil` kwarg to `try_enter`; record outcome at each exit point |
| `spec/services/entries/entry_guard_signal_recording_spec.rb` | New file — focused tests for signal outcome recording |
| `app/services/entries/bos_entry_engine.rb` | Thread `signal: nil` through `run_for` → `handle_continuation` → `attempt_entry` |
| `dashboard/src/views/Signals.vue` | Add Entry column with badge + tooltip |

---

## Task 1: `TradingSignal#record_entry_outcome`

**Files:**
- Modify: `app/models/trading_signal.rb`
- Create: `spec/models/trading_signal_spec.rb`

This is the foundation. Everything else calls this method. Test it first.

- [ ] **Step 1.1: Write the failing spec**

Create `spec/models/trading_signal_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSignal do
  let(:signal) do
    create(:trading_signal,
           index_key: 'NIFTY',
           direction: 'bullish',
           timeframe: '1m',
           supertrend_value: 23440,
           adx_value: 20.4,
           candle_timestamp: 1.minute.ago,
           signal_timestamp: Time.current,
           metadata: {})
  end

  describe '#record_entry_outcome' do
    it 'sets entry_outcome to entered and does not set entry_blocked_reason' do
      signal.record_entry_outcome('entered')

      signal.reload
      expect(signal.metadata['entry_outcome']).to eq('entered')
      expect(signal.metadata).not_to have_key('entry_blocked_reason')
    end

    it 'sets both fields when outcome is blocked' do
      signal.record_entry_outcome('blocked', 'cooldown active for index NIFTY')

      signal.reload
      expect(signal.metadata['entry_outcome']).to eq('blocked')
      expect(signal.metadata['entry_blocked_reason']).to eq('cooldown active for index NIFTY')
    end

    it 'sets both fields when outcome is skipped' do
      signal.record_entry_outcome('skipped', 'no suitable strikes')

      signal.reload
      expect(signal.metadata['entry_outcome']).to eq('skipped')
      expect(signal.metadata['entry_blocked_reason']).to eq('no suitable strikes')
    end

    it 'overwrites a prior blocked outcome when called again with entered (last-write-wins)' do
      signal.record_entry_outcome('blocked', 'circuit breaker tripped')
      signal.record_entry_outcome('entered')

      signal.reload
      expect(signal.metadata['entry_outcome']).to eq('entered')
      expect(signal.metadata).not_to have_key('entry_blocked_reason')
    end

    it 'preserves other metadata keys already on the signal' do
      signal.update!(metadata: { 'strategy' => 'supertrend_adx' })

      signal.record_entry_outcome('skipped', 'missing ATR')

      signal.reload
      expect(signal.metadata['strategy']).to eq('supertrend_adx')
      expect(signal.metadata['entry_outcome']).to eq('skipped')
    end

    it 'is a no-op when called on nil (safe navigation at call sites)' do
      nil_signal = nil
      expect { nil_signal&.record_entry_outcome('blocked', 'reason') }.not_to raise_error
    end
  end
end
```

- [ ] **Step 1.2: Check for factory**

Run: `grep -r "factory.*trading_signal\|factory :trading_signal" spec/`

If no factory exists, add one to `spec/factories/trading_signals.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :trading_signal do
    index_key { 'NIFTY' }
    direction { 'bullish' }
    timeframe { '1m' }
    supertrend_value { 23440 }
    adx_value { 20.4 }
    candle_timestamp { 1.minute.ago }
    signal_timestamp { Time.current }
    metadata { {} }
  end
end
```

- [ ] **Step 1.3: Run the spec to verify it fails**

```bash
bundle exec rspec spec/models/trading_signal_spec.rb --format documentation
```

Expected: FAIL with `undefined method 'record_entry_outcome'`

- [ ] **Step 1.4: Implement `record_entry_outcome` in the model**

In `app/models/trading_signal.rb`, add after the existing `avoid?` method (before the final `end`):

```ruby
def record_entry_outcome(outcome, reason = nil)
  update(metadata: (metadata || {}).merge(
    'entry_outcome' => outcome,
    'entry_blocked_reason' => reason
  ).compact)
end
```

Note: `compact` intentionally drops `'entry_blocked_reason'` when `reason` is `nil` (the `entered` case).

- [ ] **Step 1.5: Run the spec to verify it passes**

```bash
bundle exec rspec spec/models/trading_signal_spec.rb --format documentation
```

Expected: 6 examples, 0 failures

- [ ] **Step 1.6: Commit**

```bash
git add app/models/trading_signal.rb spec/models/trading_signal_spec.rb spec/factories/trading_signals.rb
git commit -m "feat: add TradingSignal#record_entry_outcome for entry outcome tracking"
```

---

## Task 2: `Signal::Engine` — capture signal and record skips

**Files:**
- Modify: `app/services/signal/engine.rb` (lines 493, 507–511, 530–534, 547–550, 563–566, 588–598, 600–608)

`Signal::Engine` is a large service. Only the post-signal-creation section (after line 493) is touched. All pre-creation `StateTracker.reset` calls are out of scope.

- [ ] **Step 2.1: Capture the signal return value**

On line 493, `TradingSignal.create_from_analysis(...)` is called but its return value is discarded. Change it to capture into a local variable:

Find:
```ruby
        TradingSignal.create_from_analysis(
          index_key: index_cfg[:key],
          direction: final_direction.to_s,
          timeframe: effective_timeframe,
          supertrend_value: primary_analysis[:supertrend][:last_value],
          adx_value: primary_analysis[:adx_value],
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          confidence_score: confidence_score,
          metadata: diagnostic_metadata
        )
```

Replace with:
```ruby
        signal = TradingSignal.create_from_analysis(
          index_key: index_cfg[:key],
          direction: final_direction.to_s,
          timeframe: effective_timeframe,
          supertrend_value: primary_analysis[:supertrend][:last_value],
          adx_value: primary_analysis[:adx_value],
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          confidence_score: confidence_score,
          metadata: diagnostic_metadata
        )
```

- [ ] **Step 2.2: Add a private helper method**

Find the `private` section of `Signal::Engine` and add:

```ruby
def record_signal_skip(signal, reason)
  signal&.record_entry_outcome('skipped', reason)
end
```

- [ ] **Step 2.3: Record skip at `expiry_blocked` (line 507)**

Find:
```ruby
        if expiry_blocked
          Rails.logger.info("[Signal] ExpiryModel BLOCKED #{index_cfg[:key]}: Midday decay period")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end
```

Replace with:
```ruby
        if expiry_blocked
          Rails.logger.info("[Signal] ExpiryModel BLOCKED #{index_cfg[:key]}: Midday decay period")
          record_signal_skip(signal, 'expiry midday decay')
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end
```

- [ ] **Step 2.4: Record skip at `expected_spot_move` (line 530)**

Find:
```ruby
        unless expected_spot_move&.positive?
          Rails.logger.info("[Signal] Missing expected_spot_move (ATR) -> BLOCK #{index_cfg[:key]}")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end
```

Replace with:
```ruby
        unless expected_spot_move&.positive?
          Rails.logger.info("[Signal] Missing expected_spot_move (ATR) -> BLOCK #{index_cfg[:key]}")
          record_signal_skip(signal, 'missing ATR')
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end
```

- [ ] **Step 2.5: Record skip at `picks.blank?` (line 547)**

Find:
```ruby
        if picks.blank?
          Rails.logger.warn("[Signal] No suitable option strikes found for #{index_cfg[:key]} #{final_direction}")
          return
        end
```

Replace with:
```ruby
        if picks.blank?
          Rails.logger.warn("[Signal] No suitable option strikes found for #{index_cfg[:key]} #{final_direction}")
          record_signal_skip(signal, 'no suitable strikes')
          return
        end
```

- [ ] **Step 2.6: Record skip at `mc_gate_blocked` (line 563)**

Find:
```ruby
        if mc_gate_blocked
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end
```

Replace with:
```ruby
        if mc_gate_blocked
          record_signal_skip(signal, 'market context gate')
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end
```

- [ ] **Step 2.7: Pass `signal:` to `EntryGuard.try_enter` in the supertrend loop**

Find (inside the `if supertrend_direct_entry` block, around line 588):
```ruby
          picks.each do |pick|
            entered = Entries::EntryGuard.try_enter(
              index_cfg: index_cfg,
              pick: pick,
              direction: final_direction,
              scale_multiplier: 1,
              entry_metadata: entry_metadata,
              permission: execution_permission
            )
            break if entered
          end
```

Replace with:
```ruby
          picks.each do |pick|
            entered = Entries::EntryGuard.try_enter(
              index_cfg: index_cfg,
              pick: pick,
              direction: final_direction,
              scale_multiplier: 1,
              entry_metadata: entry_metadata,
              permission: execution_permission,
              signal: signal
            )
            break if entered
          end
```

- [ ] **Step 2.8: Pass `signal:` to `BosEntryEngine.run_for`**

Find (inside the `else` branch, around line 600):
```ruby
          Entries::BosEntryEngine.run_for(
            index_cfg: index_cfg,
            instrument: instrument,
            direction: final_direction,
            picks: picks,
            entry_metadata: entry_metadata,
            permission: execution_permission
          )
```

Replace with:
```ruby
          Entries::BosEntryEngine.run_for(
            index_cfg: index_cfg,
            instrument: instrument,
            direction: final_direction,
            picks: picks,
            entry_metadata: entry_metadata,
            permission: execution_permission,
            signal: signal
          )
```

- [ ] **Step 2.9: Run full spec suite to confirm nothing broken**

```bash
bundle exec rspec --format progress
```

Expected: existing specs continue to pass (signal is `nil`-safe via `&.`)

- [ ] **Step 2.10: Commit**

```bash
git add app/services/signal/engine.rb
git commit -m "feat: capture signal in engine and record skipped outcome at 4 early-return points"
```

---

## Task 3: `EntryGuard.try_enter` — record blocked/entered outcomes

**Files:**
- Modify: `app/services/entries/entry_guard.rb`
- Create: `spec/services/entries/entry_guard_signal_recording_spec.rb`

Write the tests first. `try_enter` has many dependencies so tests use doubles for everything except the signal recording behavior.

- [ ] **Step 3.1: Write the failing spec**

Create `spec/services/entries/entry_guard_signal_recording_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard, '#try_enter signal recording' do
  let(:signal) do
    create(:trading_signal,
           index_key: 'NIFTY',
           direction: 'bullish',
           timeframe: '1m',
           supertrend_value: 23440,
           adx_value: 20.4,
           candle_timestamp: 1.minute.ago,
           signal_timestamp: Time.current,
           metadata: {})
  end

  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'NSE_FNO',
      cooldown_sec: 0
    }
  end

  let(:pick) do
    { symbol: 'NIFTY26MAR23440CE', security_id: '12345', segment: 'NSE_FNO' }
  end

  describe 'when DrawdownGuard is triggered' do
    before do
      allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(true)
    end

    it 'records skipped with drawdown_guard_active reason' do
      described_class.try_enter(
        index_cfg: index_cfg, pick: pick, direction: 'bullish', signal: signal
      )

      expect(signal.reload.metadata['entry_outcome']).to eq('skipped')
      expect(signal.reload.metadata['entry_blocked_reason']).to eq('drawdown_guard_active')
    end
  end

  describe 'when EntryPolicy blocks' do
    before do
      allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(false)
      policy_dbl = instance_double(Policies::EntryPolicy,
                                   permitted?: false,
                                   reasons: ['max_positions_reached', 'direction_locked'])
      allow(Policies::EntryPolicy).to receive(:new).and_return(policy_dbl)
    end

    it 'records blocked with joined policy reasons' do
      described_class.try_enter(
        index_cfg: index_cfg, pick: pick, direction: 'bullish', signal: signal
      )

      expect(signal.reload.metadata['entry_outcome']).to eq('blocked')
      expect(signal.reload.metadata['entry_blocked_reason']).to eq('max_positions_reached; direction_locked')
    end
  end

  describe 'when a guard pipeline guard blocks' do
    before do
      allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(false)
      policy_dbl = instance_double(Policies::EntryPolicy, permitted?: true)
      allow(Policies::EntryPolicy).to receive(:new).and_return(policy_dbl)
      allow(described_class.entry_guard_pipeline).to receive(:run).and_return(
        { blocked: 'cooldown active for index NIFTY' }
      )
    end

    it 'records blocked with the guard reason string' do
      described_class.try_enter(
        index_cfg: index_cfg, pick: pick, direction: 'bullish', signal: signal
      )

      expect(signal.reload.metadata['entry_outcome']).to eq('blocked')
      expect(signal.reload.metadata['entry_blocked_reason']).to eq('cooldown active for index NIFTY')
    end
  end

  describe 'when no signal is passed' do
    before do
      allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(true)
    end

    it 'does not raise when signal is nil' do
      expect {
        described_class.try_enter(
          index_cfg: index_cfg, pick: pick, direction: 'bullish', signal: nil
        )
      }.not_to raise_error
    end
  end
end
```

- [ ] **Step 3.2: Run to verify it fails**

```bash
bundle exec rspec spec/services/entries/entry_guard_signal_recording_spec.rb --format documentation
```

Expected: FAIL — `unknown keyword: signal` or similar

- [ ] **Step 3.3: Add `signal: nil` kwarg to `try_enter`**

In `app/services/entries/entry_guard.rb`, find the method signature:

```ruby
      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1, entry_metadata: nil, permission: nil)
```

Replace with:

```ruby
      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1, entry_metadata: nil, permission: nil, signal: nil)
```

- [ ] **Step 3.4: Record `skipped` when DrawdownGuard is triggered**

Find:
```ruby
        if Portfolio::DrawdownGuard.triggered?
          Observability::StructuredLog.info(
            event: 'entry_blocked',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s,
              stage: 'profit_protection',
              reason: 'drawdown_guard_active'
            }
          )
          return false
        end
```

Replace with:
```ruby
        if Portfolio::DrawdownGuard.triggered?
          Observability::StructuredLog.info(
            event: 'entry_blocked',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s,
              stage: 'profit_protection',
              reason: 'drawdown_guard_active'
            }
          )
          signal&.record_entry_outcome('skipped', 'drawdown_guard_active')
          return false
        end
```

- [ ] **Step 3.5: Record `blocked` when EntryPolicy rejects**

Find:
```ruby
        unless entry_policy.permitted?
          Observability::StructuredLog.info(
            event: 'entry_blocked',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s,
              stage: 'entry_policy',
              reasons: entry_policy.reasons
            }
          )
          return false
        end
```

Replace with:
```ruby
        unless entry_policy.permitted?
          Observability::StructuredLog.info(
            event: 'entry_blocked',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s,
              stage: 'entry_policy',
              reasons: entry_policy.reasons
            }
          )
          signal&.record_entry_outcome('blocked', entry_policy.reasons.join('; '))
          return false
        end
```

- [ ] **Step 3.6: Record `blocked` when the guard pipeline blocks**

Find (around line 73):
```ruby
        if result != EntryGuardPipeline::PASS
          reason = result.is_a?(Hash) ? result[:blocked] : result.to_s
          Observability::StructuredLog.info(
            event: 'entry_blocked',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s,
              stage: 'guard_pipeline',
              reason: reason.to_s
            }
          )
          return false
        end
```

Replace with:
```ruby
        if result != EntryGuardPipeline::PASS
          reason = result.is_a?(Hash) ? result[:blocked] : result.to_s
          Observability::StructuredLog.info(
            event: 'entry_blocked',
            payload: {
              service: 'Entries::EntryGuard',
              index_key: index_cfg[:key].to_s,
              symbol: pick[:symbol].to_s,
              stage: 'guard_pipeline',
              reason: reason.to_s
            }
          )
          signal&.record_entry_outcome('blocked', reason.to_s)
          return false
        end
```

- [ ] **Step 3.7: Record `entered` after successful tracker creation**

Find (around line 273):
```ruby
        mark_bos_consumed!(index_cfg: index_cfg, bos_context: bos_context) if tracker

        Rails.logger.info("[EntryGuard] Successfully placed order #{order_no} for #{index_cfg[:key]}: #{pick[:symbol]}")
```

Replace with:
```ruby
        mark_bos_consumed!(index_cfg: index_cfg, bos_context: bos_context) if tracker
        signal&.record_entry_outcome('entered') if tracker

        Rails.logger.info("[EntryGuard] Successfully placed order #{order_no} for #{index_cfg[:key]}: #{pick[:symbol]}")
```

- [ ] **Step 3.8: Run the signal recording spec**

```bash
bundle exec rspec spec/services/entries/entry_guard_signal_recording_spec.rb --format documentation
```

Expected: 4 examples, 0 failures

- [ ] **Step 3.9: Run full suite to confirm no regressions**

```bash
bundle exec rspec --format progress
```

Expected: all existing specs pass

- [ ] **Step 3.10: Commit**

```bash
git add app/services/entries/entry_guard.rb spec/services/entries/entry_guard_signal_recording_spec.rb
git commit -m "feat: record entry outcome in EntryGuard (blocked/skipped/entered)"
```

---

## Task 4: `BosEntryEngine` — thread `signal:` through private call chain

**Files:**
- Modify: `app/services/entries/bos_entry_engine.rb`

The chain is `run_for` → `handle_continuation` → `attempt_entry` → `EntryGuard.try_enter`. `run_for` uses keyword args; `handle_continuation` and `attempt_entry` use positional args — add `signal: nil` as a trailing keyword arg to each without touching the positional args.

- [ ] **Step 4.1: Add `signal: nil` to `run_for`**

Find:
```ruby
      def run_for(index_cfg:, instrument:, direction:, picks:, entry_metadata:, permission:)
```

Replace with:
```ruby
      def run_for(index_cfg:, instrument:, direction:, picks:, entry_metadata:, permission:, signal: nil)
```

- [ ] **Step 4.2: Forward `signal:` from `run_for` to `handle_continuation`**

There is one call site (line 69). Find:

```ruby
          outcome = handle_continuation(series, state, index_cfg, instrument, direction, picks, entry_metadata, permission, timeframe)
```

Replace with:

```ruby
          outcome = handle_continuation(series, state, index_cfg, instrument, direction, picks, entry_metadata, permission, timeframe, signal: signal)
```

- [ ] **Step 4.3: Add `signal: nil` to `handle_continuation`**

Find:
```ruby
      def handle_continuation(series, state, index_cfg, instrument, direction, picks, entry_metadata, permission, timeframe)
```

Replace with:
```ruby
      def handle_continuation(series, state, index_cfg, instrument, direction, picks, entry_metadata, permission, timeframe, signal: nil)
```

- [ ] **Step 4.4: Forward `signal:` from `handle_continuation` to `attempt_entry`**

There is one call site (line 161). Find:

```ruby
          entered = attempt_entry(index_cfg, direction, picks, entry_metadata, permission)
```

Replace with:

```ruby
          entered = attempt_entry(index_cfg, direction, picks, entry_metadata, permission, signal: signal)
```

- [ ] **Step 4.5: Add `signal: nil` to `attempt_entry`**

Find:
```ruby
      def attempt_entry(index_cfg, direction, picks, entry_metadata, permission)
```

Replace with:
```ruby
      def attempt_entry(index_cfg, direction, picks, entry_metadata, permission, signal: nil)
```

- [ ] **Step 4.6: Forward `signal:` to `EntryGuard.try_enter` inside `attempt_entry`**

Find:
```ruby
          result = Entries::EntryGuard.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: direction,
            scale_multiplier: 1,
            entry_metadata: entry_metadata,
            permission: permission
          )
```

Replace with:
```ruby
          result = Entries::EntryGuard.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: direction,
            scale_multiplier: 1,
            entry_metadata: entry_metadata,
            permission: permission,
            signal: signal
          )
```

- [ ] **Step 4.7: Run full spec suite**

```bash
bundle exec rspec --format progress
```

Expected: all pass

- [ ] **Step 4.8: Commit**

```bash
git add app/services/entries/bos_entry_engine.rb
git commit -m "feat: thread signal kwarg through BosEntryEngine call chain"
```

---

## Task 5: Frontend — Entry column in `Signals.vue`

**Files:**
- Modify: `dashboard/src/views/Signals.vue`

- [ ] **Step 5.1: Add computed fields to `processedSignals`**

In the `processedSignals` computed, inside the `.map(sig => ({...}))` object, add after `confidenceClass`:

```js
    entryOutcome: sig.metadata?.entry_outcome || 'pending',
    entryBlockedReason: sig.metadata?.entry_blocked_reason || null,
```

- [ ] **Step 5.2: Add `getEntryOutcomeStyle` helper**

Add a new function below `getConfidenceClass`:

```js
function getEntryOutcomeStyle(outcome) {
  switch (outcome) {
    case 'entered':
      return { cls: 'text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 rounded-full', label: '● ENTERED' }
    case 'blocked':
      return { cls: 'text-amber-400 bg-amber-500/10 border border-amber-500/20 rounded-full', label: '✗ BLOCKED' }
    case 'skipped':
      return { cls: 'text-gray-500 bg-gray-500/10 border border-gray-500/20 rounded-full', label: '◌ SKIPPED' }
    default:
      return { cls: 'text-gray-600', label: '— —' }
  }
}
```

- [ ] **Step 5.3: Add the table header**

In `<thead>`, after the Strategy `<th>`:

```html
<th class="p-6 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5">Entry</th>
```

- [ ] **Step 5.4: Add the table cell**

In the `<tr v-for="sig in processedSignals">` row, after the Strategy `<td>`:

```html
<td class="p-6">
  <span
    :class="['px-3 py-1 text-[9px] font-black uppercase tracking-widest inline-block', getEntryOutcomeStyle(sig.entryOutcome).cls]"
    :title="sig.entryBlockedReason || ''"
  >
    {{ getEntryOutcomeStyle(sig.entryOutcome).label }}
  </span>
</td>
```

- [ ] **Step 5.5: Update `colspan` on the empty-state row**

Find:
```html
<td colspan="6" class="p-20 text-center">
```

Replace with:
```html
<td colspan="7" class="p-20 text-center">
```

- [ ] **Step 5.6: Verify in browser**

Start the dev server if not running:
```bash
cd dashboard && npm run dev
```

Open the Signals tab. Confirm:
- New "Entry" column appears between Strategy and Analysis
- Rows with no outcome show `— —` in muted gray
- A signal with `entry_outcome: "blocked"` shows amber `✗ BLOCKED`
- Hovering over a blocked/skipped badge shows the reason in a browser tooltip

- [ ] **Step 5.7: Commit**

```bash
git add dashboard/src/views/Signals.vue
git commit -m "feat: add entry outcome badge column to signals table"
```

---

## Task 6: Smoke check end-to-end

- [ ] **Step 6.1: Run full spec suite**

```bash
bundle exec rspec --format progress
```

Expected: all pass, 0 failures

- [ ] **Step 6.2: Run RuboCop on changed Ruby files**

```bash
bundle exec rubocop app/models/trading_signal.rb app/services/signal/engine.rb app/services/entries/entry_guard.rb app/services/entries/bos_entry_engine.rb
```

Fix any offenses.

- [ ] **Step 6.3: Verify `metadata` serialization via the API**

Start the Rails server and curl the dashboard endpoint:

```bash
curl -s http://localhost:3001/api/dashboard | jq '.recent_signals[0] | {entry_outcome: .metadata.entry_outcome, entry_blocked_reason: .metadata.entry_blocked_reason}'
```

Expected: JSON showing `entry_outcome` key (value is `null` or a string — both are fine depending on whether any signals have been processed since deploy).

- [ ] **Step 6.4: Final commit (if any cleanup needed)**

```bash
git add -p
git commit -m "chore: rubocop fixes for signal entry outcome tracking"
```
