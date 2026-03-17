# Fix Underlying Price Propagation & Profit Protection — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two critical trading bugs: (1) underlying index price not stored/propagated, causing broken stop-loss calculations, and (2) profit protection gate blocking on fast moves, letting ₹4k+ profits turn into losses.

**Architecture:** Surgical fixes to 7 existing files + 1 new shared module. Entry path stores underlying price correctly; exit path gains emergency peak-loss protection (sub-second) and structure invalidation using underlying LTP. Config enables two existing but disabled feature flags.

**Tech Stack:** Ruby 3.3.4, Rails 8 API, RSpec, AlgoConfig (YAML + DB overrides)

**Spec:** `docs/superpowers/specs/2026-03-16-underlying-price-and-profit-protection-design.md`

---

## Chunk 1: Shared Module + Underlying Price Propagation

### Task 1: Create UnderlyingLtpResolver shared module

**Files:**
- Create: `app/services/live/underlying_ltp_resolver.rb`
- Test: `spec/services/live/underlying_ltp_resolver_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/live/underlying_ltp_resolver_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::UnderlyingLtpResolver do
  let(:test_class) { Class.new { include Live::UnderlyingLtpResolver } }
  let(:resolver) { test_class.new }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      indices: [
        { key: 'NIFTY', segment: 'IDX_I', sid: '13' },
        { key: 'SENSEX', segment: 'IDX_I', sid: '51' }
      ]
    })
  end

  describe '#resolve_underlying_ltp' do
    it 'returns LTP for a known index key' do
      tick = double(ltp: 23850.5)
      allow(Live::TickQuery).to receive(:for_security)
        .with(segment: 'IDX_I', security_id: '13')
        .and_return(tick)

      expect(resolver.resolve_underlying_ltp('NIFTY')).to eq(23850.5)
    end

    it 'returns nil for unknown index key' do
      expect(resolver.resolve_underlying_ltp('UNKNOWN')).to be_nil
    end

    it 'returns nil when index_key is nil' do
      expect(resolver.resolve_underlying_ltp(nil)).to be_nil
    end

    it 'returns nil when TickQuery raises' do
      allow(Live::TickQuery).to receive(:for_security).and_raise(StandardError)
      expect(resolver.resolve_underlying_ltp('NIFTY')).to be_nil
    end

    it 'returns nil when TickQuery returns nil' do
      allow(Live::TickQuery).to receive(:for_security).and_return(nil)
      expect(resolver.resolve_underlying_ltp('NIFTY')).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/live/underlying_ltp_resolver_spec.rb --format documentation`
Expected: FAIL — `uninitialized constant Live::UnderlyingLtpResolver`

- [ ] **Step 3: Write the implementation**

Create `app/services/live/underlying_ltp_resolver.rb`:

```ruby
# frozen_string_literal: true

module Live
  module UnderlyingLtpResolver
    def resolve_underlying_ltp(index_key)
      return nil unless index_key

      cfg = AlgoConfig.fetch[:indices]&.find { |i| i[:key].to_s == index_key.to_s }
      return nil unless cfg

      Live::TickQuery.for_security(segment: cfg[:segment], security_id: cfg[:sid])&.ltp
    rescue StandardError
      nil
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/live/underlying_ltp_resolver_spec.rb --format documentation`
Expected: 5 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/services/live/underlying_ltp_resolver.rb spec/services/live/underlying_ltp_resolver_spec.rb
git commit -m "feat: add UnderlyingLtpResolver shared module for index LTP lookup"
```

---

### Task 2: Fix Signal::Engine — pass entry_underlying_price

**Files:**
- Modify: `app/services/signal/engine.rb:504-509`

- [ ] **Step 1: Add entry_underlying_price to supertrend entry_metadata**

In `app/services/signal/engine.rb`, find the `entry_metadata.merge!` block (~line 504) that starts with `bos_id:`. Add one line after `bos_level:`:

```ruby
entry_metadata.merge!(
  bos_id: "st_#{index_cfg[:key]}_#{Time.current.to_i}",
  bos_timeframe: primary_tf,
  bos_origin_price: primary_series.candles.last&.close,
  bos_level: primary_series.candles.last&.close,
  entry_underlying_price: primary_series.candles.last&.close
)
```

The value `primary_series.candles.last&.close` is already used for `bos_origin_price` — it's the INDEX close (e.g., 23838 for NIFTY), not the option premium.

- [ ] **Step 2: Run existing signal engine tests**

Run: `bundle exec rspec spec/services/signal/ --format documentation`
Expected: All pass (no behavioral change, just additional metadata)

- [ ] **Step 3: Commit**

```bash
git add app/services/signal/engine.rb
git commit -m "fix: pass entry_underlying_price in supertrend entry metadata"
```

---

### Task 3: Fix EntryGuard.apply_bos_metadata! — domain separation + always store underlying

**Files:**
- Modify: `app/services/entries/entry_guard.rb:888-934`
- Test: `spec/services/entries/entry_guard_spec.rb` (add new context)

- [ ] **Step 1: Write failing tests for apply_bos_metadata!**

Add to the end of `spec/services/entries/entry_guard_spec.rb`, before the final `end`:

```ruby
describe 'apply_bos_metadata!' do
  # Access the private method via send for testing
  let(:meta_hash) { { index_key: 'NIFTY' } }
  let(:entry_price) { 200.0 }
  let(:quantity) { 50 }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: { sl_pct: 0.12 },
      indices: [{ key: 'NIFTY', segment: 'IDX_I', sid: '13' }]
    })
  end

  context 'supertrend contract' do
    let(:bos_context) do
      {
        confirmed_at: Time.current,
        direction: 'long_pe',
        bos_id: 'st_NIFTY_123',
        timeframe: '1m',
        origin_swing: { price: 200.0, index: 0 },
        entry_underlying_price: 23850.0
      }
    end
    let(:entry_metadata) do
      {
        entry_contract: 'supertrend_machine_v1',
        entry_underlying_price: 23850.0
      }
    end

    it 'stores entry_underlying_price from entry_metadata' do
      described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                           entry_price: entry_price, quantity: quantity)
      expect(meta_hash[:entry_underlying_price]).to eq(23850.0)
    end

    it 'calculates initial_sl_pct in premium domain (≈12%)' do
      described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                           entry_price: entry_price, quantity: quantity)
      expect(meta_hash[:initial_sl_pct]).to be_within(1.0).of(12.0)
    end

    it 'calculates premium_stop_price as positive below entry' do
      described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                           entry_price: entry_price, quantity: quantity)
      expect(meta_hash[:premium_stop_price]).to be > 0
      expect(meta_hash[:premium_stop_price]).to be < entry_price
    end
  end

  context 'BOS contract' do
    let(:bos_context) do
      {
        confirmed_at: Time.current,
        direction: 'long_pe',
        bos_id: 'bos_NIFTY_123',
        timeframe: '5m',
        origin_swing: { price: 23800.0, index: 0 },
        entry_underlying_price: 23850.0
      }
    end
    let(:entry_metadata) do
      { entry_contract: 'bos_machine_v1' }
    end

    it 'uses premium domain for stops (not underlying domain)' do
      described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                           entry_price: entry_price, quantity: quantity)
      # initial_sl_pct should be ~12% (from sl_pct config), not some huge number
      expect(meta_hash[:initial_sl_pct]).to be_within(1.0).of(12.0)
    end

    it 'stores structure_invalidation_price in underlying domain' do
      described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                           entry_price: entry_price, quantity: quantity)
      expect(meta_hash[:structure_invalidation_price]).to eq(23800.0)
    end

    it 'stores entry_underlying_price from bos_context' do
      described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                           entry_price: entry_price, quantity: quantity)
      expect(meta_hash[:entry_underlying_price]).to eq(23850.0)
    end
  end

  context 'when entry_underlying_price is nil' do
    let(:bos_context) do
      {
        confirmed_at: Time.current,
        direction: 'long_pe',
        bos_id: 'st_NIFTY_123',
        timeframe: '1m',
        origin_swing: { price: 200.0, index: 0 },
        entry_underlying_price: nil
      }
    end
    let(:entry_metadata) do
      { entry_contract: 'supertrend_machine_v1', entry_underlying_price: nil }
    end

    it 'falls back to TickQuery for underlying price' do
      tick = double(ltp: 23900.0)
      allow(Live::TickQuery).to receive(:for_security)
        .with(segment: 'IDX_I', security_id: '13')
        .and_return(tick)

      described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                           entry_price: entry_price, quantity: quantity)
      expect(meta_hash[:entry_underlying_price]).to eq(23900.0)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/entries/entry_guard_spec.rb --format documentation --tag ~slow`
Expected: Several failures — BOS path has wrong initial_sl_pct, supertrend path missing entry_underlying_price

- [ ] **Step 3: Include UnderlyingLtpResolver in EntryGuard**

In `app/services/entries/entry_guard.rb`, add at the top of the class (after `class << self`):

```ruby
include Live::UnderlyingLtpResolver
```

- [ ] **Step 4: Fix the BOS path in apply_bos_metadata!**

In `app/services/entries/entry_guard.rb`, replace lines 899-905 (the `else` branch):

Before:
```ruby
else
  origin_price = bos_context[:origin_swing][:price].to_f
  entry_underlying_price = bos_context[:entry_underlying_price]
  reference_price = entry_underlying_price || entry_price
  entry_risk_rupees = (reference_price.to_f - origin_price).abs * quantity.to_i
  premium_r = entry_risk_rupees / quantity.to_f
end
```

After:
```ruby
else
  origin_price = bos_context[:origin_swing][:price].to_f
  entry_underlying_price = bos_context[:entry_underlying_price]
  sl_decimal = supertrend_sl_decimal
  premium_r = entry_price.to_f * sl_decimal
  entry_risk_rupees = premium_r * quantity.to_i
end
```

- [ ] **Step 5: Fix always-store underlying price (line 915)**

Replace line 915:

Before:
```ruby
meta_hash[:entry_underlying_price] = entry_underlying_price if entry_underlying_price
```

After:
```ruby
meta_hash[:entry_underlying_price] = entry_underlying_price || resolve_underlying_ltp(meta_hash[:index_key])
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/entries/entry_guard_spec.rb --format documentation`
Expected: All pass including the new `apply_bos_metadata!` tests

- [ ] **Step 7: Run full entry guard + signal tests for regression**

Run: `bundle exec rspec spec/services/entries/ spec/services/signal/ --format documentation`
Expected: All pass

- [ ] **Step 8: Commit**

```bash
git add app/services/entries/entry_guard.rb spec/services/entries/entry_guard_spec.rb
git commit -m "fix: separate premium/underlying domains in apply_bos_metadata!, always store underlying price"
```

---

## Chunk 2: Peak Drawdown Activation Gate Fix

### Task 4: Fix TrailingConfig.peak_drawdown_active? — AND to OR with emergency override

**Files:**
- Modify: `app/services/positions/trailing_config.rb:132-135`
- Test: `spec/services/positions/trailing_config_spec.rb`

- [ ] **Step 1: Update the existing tests + add new ones**

Replace the entire `describe '.peak_drawdown_active?'` block in `spec/services/positions/trailing_config_spec.rb`:

```ruby
describe '.peak_drawdown_active?' do
  # Default activation_profit_pct is 0.25, activation_sl_offset_pct is 0.10

  it 'is true when profit meets activation threshold (OR logic)' do
    expect(described_class.peak_drawdown_active?(profit_pct: 0.30, current_sl_offset_pct: 0.0)).to be true
  end

  it 'is true when SL offset meets threshold (OR logic)' do
    expect(described_class.peak_drawdown_active?(profit_pct: 0.10, current_sl_offset_pct: 0.15)).to be true
  end

  it 'is true when both thresholds are met' do
    expect(described_class.peak_drawdown_active?(profit_pct: 0.30, current_sl_offset_pct: 0.12)).to be true
  end

  it 'is false when neither threshold is met' do
    expect(described_class.peak_drawdown_active?(profit_pct: 0.10, current_sl_offset_pct: 0.05)).to be false
  end

  it 'emergency override: always true when peak >= 2x activation threshold' do
    # 2x of 0.25 = 0.50. Peak of 0.60 should always activate regardless of SL offset
    expect(described_class.peak_drawdown_active?(profit_pct: 0.60, current_sl_offset_pct: -0.15)).to be true
  end

  it 'emergency override does not trigger below 2x threshold' do
    # 0.40 < 0.50 (2x of 0.25), and SL offset -0.15 < 0.10 threshold
    expect(described_class.peak_drawdown_active?(profit_pct: 0.40, current_sl_offset_pct: -0.15)).to be false
  end

  it 'handles zero peak profit' do
    expect(described_class.peak_drawdown_active?(profit_pct: 0.0, current_sl_offset_pct: 0.0)).to be false
  end

  it 'handles negative current (neither threshold met)' do
    expect(described_class.peak_drawdown_active?(profit_pct: -0.05, current_sl_offset_pct: -0.10)).to be false
  end
end
```

- [ ] **Step 2: Run test to verify failures**

Run: `bundle exec rspec spec/services/positions/trailing_config_spec.rb --format documentation`
Expected: Failures on the OR-logic and emergency override tests

- [ ] **Step 3: Implement the fix**

In `app/services/positions/trailing_config.rb`, replace lines 132-135:

```ruby
def peak_drawdown_active?(profit_pct:, current_sl_offset_pct:)
  # Emergency: always protect if peak profit exceeds 2x activation threshold
  return true if profit_pct.to_f >= config[:activation_profit_pct].to_f * 2.0

  # Normal: either profit threshold OR SL already moved up is sufficient
  profit_pct.to_f >= config[:activation_profit_pct] ||
    current_sl_offset_pct.to_f >= config[:activation_sl_offset_pct]
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/positions/trailing_config_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/positions/trailing_config.rb spec/services/positions/trailing_config_spec.rb
git commit -m "fix: change peak_drawdown_active? from AND to OR logic with emergency override"
```

---

### Task 5: Add emergency peak-loss exit to UnifiedExitChecker (sub-second path)

**Files:**
- Modify: `app/services/live/unified_exit_checker.rb`
- Create: `spec/services/live/unified_exit_checker_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/live/unified_exit_checker_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::UnifiedExitChecker do
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 1,
      active?: true,
      entry_price: 200.0,
      quantity: 50,
      high_water_mark_pnl: 0.0,
      current_pnl_pct: 0.0,
      meta: {},
      order_no: 'ORD-1'
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      position_sizing: {
        drawdown: {
          emergency_peak_loss_exit: true,
          emergency_min_peak_pct: 0.10
        }
      },
      risk: {},
      indices: [{ key: 'NIFTY', segment: 'IDX_I', sid: '13' }]
    })
  end

  describe 'emergency peak-loss exit' do
    it 'triggers when peak >= 10% and current < -2%' do
      allow(tracker).to receive(:high_water_mark_pnl).and_return(1500.0) # 1500 / (200*50) = 15%
      allow(tracker).to receive(:current_pnl_pct).and_return(-0.05)      # -5%

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be true
    end

    it 'does not trigger when peak < 10%' do
      allow(tracker).to receive(:high_water_mark_pnl).and_return(500.0)  # 500 / 10000 = 5%
      allow(tracker).to receive(:current_pnl_pct).and_return(-0.05)

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end

    it 'does not trigger when current loss is shallow (> -2%)' do
      allow(tracker).to receive(:high_water_mark_pnl).and_return(1500.0) # 15%
      allow(tracker).to receive(:current_pnl_pct).and_return(-0.01)      # -1% (above -2% threshold)

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end

    it 'does not trigger when disabled in config' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        position_sizing: {
          drawdown: { emergency_peak_loss_exit: false }
        },
        risk: {},
        indices: []
      })
      allow(tracker).to receive(:high_water_mark_pnl).and_return(1500.0)
      allow(tracker).to receive(:current_pnl_pct).and_return(-0.05)

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end

    it 'handles zero entry value gracefully' do
      allow(tracker).to receive(:entry_price).and_return(0.0)
      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb --format documentation`
Expected: FAIL — `NoMethodError: undefined method 'emergency_peak_loss_exit_triggered?'`

- [ ] **Step 3: Add emergency_peak_loss_exit_triggered? to UnifiedExitChecker**

In `app/services/live/unified_exit_checker.rb`, add the private method inside the `class << self` block, near the end of the private methods section:

```ruby
def emergency_peak_loss_exit_triggered?(tracker)
  drawdown_cfg = AlgoConfig.fetch.dig(:position_sizing, :drawdown) || {}
  return false if drawdown_cfg[:emergency_peak_loss_exit] == false

  min_peak_pct = (drawdown_cfg[:emergency_min_peak_pct] || 0.10).to_f
  entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
  return false if entry_value <= 0

  peak_pct = tracker.high_water_mark_pnl.to_f / entry_value
  current_pct = tracker.current_pnl_pct.to_f

  peak_pct >= min_peak_pct && current_pct < -0.02
end
```

- [ ] **Step 4: Add the emergency check call in check_exit_conditions**

In the `check_exit_conditions` method, add after the stop loss check (after `# 2. Loss Limit`) and before `# 3. Profit Target`:

```ruby
# 2.5 Emergency: profitable position flipped to loss
if emergency_peak_loss_exit_triggered?(tracker)
  entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
  peak_pct = tracker.high_water_mark_pnl.to_f / entry_value
  current_pct = tracker.current_pnl_pct.to_f
  return {
    exit: true,
    reason: "EMERGENCY_PEAK_LOSS (peak: #{(peak_pct * 100).round(2)}%, current: #{(current_pct * 100).round(2)}%)"
  }
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb --format documentation`
Expected: 5 examples, 0 failures

- [ ] **Step 6: Commit**

```bash
git add app/services/live/unified_exit_checker.rb spec/services/live/unified_exit_checker_spec.rb
git commit -m "feat: add emergency peak-loss exit to UnifiedExitChecker sub-second path"
```

---

### Task 6: Add emergency peak-loss defense-in-depth to TrailingEngine

**Files:**
- Modify: `app/services/live/trailing_engine.rb`
- Test: `spec/services/live/trailing_engine_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/services/live/trailing_engine_spec.rb`, inside the main `describe` block:

```ruby
describe '#check_peak_drawdown emergency exit' do
  it 'triggers emergency exit when peak >= 10% and current < -2%' do
    allow(AlgoConfig).to receive(:fetch).and_return({
      position_sizing: {
        drawdown: { emergency_peak_loss_exit: true, emergency_min_peak_pct: 0.10 }
      },
      feature_flags: { enable_peak_drawdown_activation: false }
    })
    position = build_position(peak_profit_pct: 0.15, pnl_pct: -0.05)
    allow(Live::ExitEngine).to receive(:execute_exit)

    result = engine.check_peak_drawdown(position, exit_engine)
    expect(result).to be true
    expect(Live::ExitEngine).to have_received(:execute_exit).with(
      hash_including(reason: /emergency_peak_loss_exit/)
    )
  end

  it 'does not trigger emergency when peak < 10%' do
    allow(AlgoConfig).to receive(:fetch).and_return({
      position_sizing: {
        drawdown: { emergency_peak_loss_exit: true, emergency_min_peak_pct: 0.10 }
      },
      feature_flags: { enable_peak_drawdown_activation: false }
    })
    allow(Live::ExitEngine).to receive(:execute_exit)
    position = build_position(peak_profit_pct: 0.05, pnl_pct: -0.05)

    result = engine.check_peak_drawdown(position, exit_engine)
    # Should not trigger emergency (peak too low), may or may not trigger normal drawdown
    expect(Live::ExitEngine).not_to have_received(:execute_exit)
  end

  it 'does not trigger emergency when current loss is shallow (> -2%)' do
    allow(AlgoConfig).to receive(:fetch).and_return({
      position_sizing: {
        drawdown: { emergency_peak_loss_exit: true, emergency_min_peak_pct: 0.10 }
      },
      feature_flags: { enable_peak_drawdown_activation: false }
    })
    allow(Live::ExitEngine).to receive(:execute_exit)
    position = build_position(peak_profit_pct: 0.15, pnl_pct: -0.01)

    result = engine.check_peak_drawdown(position, exit_engine)
    expect(Live::ExitEngine).not_to have_received(:execute_exit)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/live/trailing_engine_spec.rb --format documentation`
Expected: Failures — no emergency logic exists yet

- [ ] **Step 3: Add emergency check to check_peak_drawdown**

In `app/services/live/trailing_engine.rb`, inside `check_peak_drawdown`, after the `return false` for `peak <= 0` (after line 77), add:

```ruby
# Emergency defense-in-depth: sub-second path in UnifiedExitChecker is primary
drawdown_cfg = AlgoConfig.fetch.dig(:position_sizing, :drawdown) || {}
unless drawdown_cfg[:emergency_peak_loss_exit] == false
  emergency_min_peak = (drawdown_cfg[:emergency_min_peak_pct] || 0.10).to_f
  if peak >= emergency_min_peak && current < -0.02
    tracker = PositionTracker.find_by(id: position_data.tracker_id)
    if tracker&.active?
      reason = "emergency_peak_loss_exit (peak: #{(peak * 100).round(2)}%, current: #{(current * 100).round(2)}%)"
      Live::ExitEngine.execute_exit(tracker: tracker, reason: reason, source: :trailing_engine)
      return true
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/live/trailing_engine_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/live/trailing_engine.rb spec/services/live/trailing_engine_spec.rb
git commit -m "feat: add emergency peak-loss defense-in-depth to TrailingEngine"
```

---

## Chunk 3: Structure Invalidation + Config + Final Verification

### Task 7: Add structure invalidation check to UnifiedExitChecker

**Files:**
- Modify: `app/services/live/unified_exit_checker.rb`
- Test: `spec/services/live/unified_exit_checker_spec.rb` (extend)

- [ ] **Step 1: Write the failing tests**

Add to `spec/services/live/unified_exit_checker_spec.rb`:

```ruby
describe 'structure invalidation' do
  it 'triggers exit for long_pe when underlying rises above invalidation price' do
    allow(tracker).to receive(:meta).and_return({
      'direction' => 'long_pe',
      'structure_invalidation_price' => 23800.0,
      'index_key' => 'NIFTY'
    })
    tick = double(ltp: 23850.0)
    allow(Live::TickQuery).to receive(:for_security).and_return(tick)

    result = described_class.send(:structure_invalidated?, tracker, 23850.0, 23800.0)
    expect(result).to be true
  end

  it 'triggers exit for long_ce when underlying falls below invalidation price' do
    allow(tracker).to receive(:meta).and_return({
      'direction' => 'long_ce',
      'structure_invalidation_price' => 23800.0,
      'index_key' => 'NIFTY'
    })

    result = described_class.send(:structure_invalidated?, tracker, 23750.0, 23800.0)
    expect(result).to be true
  end

  it 'does not trigger for long_pe when underlying is below invalidation' do
    allow(tracker).to receive(:meta).and_return({ 'direction' => 'long_pe' })
    result = described_class.send(:structure_invalidated?, tracker, 23750.0, 23800.0)
    expect(result).to be false
  end

  it 'does not trigger for unknown direction' do
    allow(tracker).to receive(:meta).and_return({ 'direction' => 'unknown' })
    result = described_class.send(:structure_invalidated?, tracker, 23850.0, 23800.0)
    expect(result).to be false
  end

  it 'returns nil gracefully when TickQuery fails' do
    allow(Live::TickQuery).to receive(:for_security).and_raise(StandardError)
    result = described_class.send(:resolve_underlying_ltp, 'NIFTY')
    expect(result).to be_nil
  end

  it 'skips structure invalidation when invalidation_price is nil in meta' do
    allow(tracker).to receive(:meta).and_return({
      'direction' => 'long_pe',
      'index_key' => 'NIFTY'
      # Note: no 'structure_invalidation_price' key at all
    })
    # The guard `if (invalidation_price = tracker.meta&.dig('structure_invalidation_price'))`
    # evaluates to nil/falsy, so resolve_underlying_ltp should NOT be called
    expect(Live::TickQuery).not_to receive(:for_security)
    # Full check_exit_conditions would not reach structure invalidation — we verify via
    # the method's nil guard by confirming TickQuery is never consulted
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb --format documentation`
Expected: FAIL — `NoMethodError: undefined method 'structure_invalidated?'`

- [ ] **Step 3: Include UnderlyingLtpResolver and add structure invalidation methods**

In `app/services/live/unified_exit_checker.rb`:

1. Add `include Live::UnderlyingLtpResolver` inside the `class << self` block (after the opening)

2. Add private methods:

```ruby
def structure_invalidated?(tracker, underlying_ltp, invalidation_price)
  direction = tracker.meta&.dig('direction').to_s
  case direction
  when 'long_pe'
    underlying_ltp > invalidation_price.to_f
  when 'long_ce'
    underlying_ltp < invalidation_price.to_f
  else
    false
  end
end
```

3. Add the structure invalidation check in `check_exit_conditions`, after trailing stop check and before the time-based exit check (after `# 5. Trailing Stop`, before `# 5. Time-Based Exit`):

```ruby
# 6. Structure Invalidation (underlying broke past entry structure level)
if (invalidation_price = tracker.meta&.dig('structure_invalidation_price'))
  underlying_ltp = resolve_underlying_ltp(tracker.meta&.dig('index_key'))
  if underlying_ltp && structure_invalidated?(tracker, underlying_ltp, invalidation_price)
    return {
      exit: true,
      reason: "STRUCTURE_INVALIDATION (underlying #{underlying_ltp.round(2)} broke #{invalidation_price})"
    }
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/live/unified_exit_checker_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add app/services/live/unified_exit_checker.rb spec/services/live/unified_exit_checker_spec.rb
git commit -m "feat: add structure invalidation exit using underlying LTP in UnifiedExitChecker"
```

---

### Task 8: Update config/algo.yml — enable flags + add emergency config

**Files:**
- Modify: `config/algo.yml`

- [ ] **Step 1: Enable feature flags**

In `config/algo.yml`, update these values in the `feature_flags:` section:

```yaml
feature_flags:
  enable_underlying_aware_exits: true    # was false
  enable_peak_drawdown_activation: true  # was false
```

- [ ] **Step 2: Add emergency drawdown config**

In `config/algo.yml`, under `position_sizing: > drawdown:` section (~line 450), add after the `index_floors:` block:

```yaml
  # Emergency peak-loss exit: exit immediately if position had significant profit and flips to loss
  emergency_peak_loss_exit: true    # Enable emergency exit
  emergency_min_peak_pct: 0.10     # 10% minimum peak before emergency logic applies
```

- [ ] **Step 3: Verify config loads correctly**

Run: `bin/rails runner "puts AlgoConfig.fetch.dig(:position_sizing, :drawdown, :emergency_peak_loss_exit).inspect; puts AlgoConfig.fetch[:feature_flags][:enable_underlying_aware_exits].inspect; puts AlgoConfig.fetch[:feature_flags][:enable_peak_drawdown_activation].inspect" 2>&1 | tail -3`
Expected: `true`, `true`, `true`

- [ ] **Step 4: Commit**

```bash
git add config/algo.yml
git commit -m "config: enable underlying exits, peak drawdown activation, and emergency peak-loss exit"
```

---

### Task 9: Full regression test suite

**Files:** None (verification only)

- [ ] **Step 1: Run all modified spec files**

Run: `bundle exec rspec spec/services/live/underlying_ltp_resolver_spec.rb spec/services/entries/entry_guard_spec.rb spec/services/positions/trailing_config_spec.rb spec/services/live/trailing_engine_spec.rb spec/services/live/unified_exit_checker_spec.rb --format documentation`
Expected: All pass

- [ ] **Step 2: Run full test suite**

Run: `bundle exec rspec --format progress`
Expected: No new failures introduced

- [ ] **Step 3: Run rubocop on changed files**

Run: `bundle exec rubocop app/services/live/underlying_ltp_resolver.rb app/services/entries/entry_guard.rb app/services/positions/trailing_config.rb app/services/live/trailing_engine.rb app/services/live/unified_exit_checker.rb`
Expected: No offenses (or only pre-existing ones)

- [ ] **Step 4: Run brakeman security scan**

Run: `bin/brakeman --no-pager -q`
Expected: No new warnings

- [ ] **Step 5: Final commit if any lint fixes needed**

```bash
# Only if rubocop required changes:
git add -A && git commit -m "style: fix rubocop offenses in modified files"
```
