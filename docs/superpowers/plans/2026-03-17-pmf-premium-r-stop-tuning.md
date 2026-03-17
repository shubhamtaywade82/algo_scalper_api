# PMF & PREMIUM_R_STOP Tuning Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PMF session+index aware with configurable stall windows, and suppress PREMIUM_R_STOP when trailing is armed.

**Architecture:** Shared `SessionDetector` concern for session detection. Config-driven PMF stall resolution. R-stop suppression via trailing-armed check in enforcement loop.

**Tech Stack:** Ruby 3.3.4, Rails 8, RSpec

**Spec:** `docs/superpowers/specs/2026-03-17-pmf-premium-r-stop-tuning-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `app/services/concerns/session_detector.rb` | CREATE | Shared session detection from `risk.time_regimes` config |
| `app/services/signal/entry_quality_filter.rb` | MODIFY | Replace private `detect_current_session` with `include SessionDetector` |
| `app/services/risk/rules/premium_momentum_failure_rule.rb` | MODIFY | Config-driven stall minutes with index+session resolution |
| `app/services/live/risk_manager_service/exit_enforcement.rb` | MODIFY | R-stop suppression when trailing armed |
| `config/algo.yml` | MODIFY | Add PMF config section |
| `config/profiles/exit_testing.yml` | MODIFY | Mirror PMF config |
| `spec/services/concerns/session_detector_spec.rb` | CREATE | Tests for shared session detection |
| `spec/services/risk/rules/premium_momentum_failure_rule_spec.rb` | CREATE | Tests for session+index stall resolution |
| `spec/services/live/risk_manager_service/exit_enforcement_spec.rb` | CREATE | Tests for R-stop suppression / trailing_armed_for? |

---

## Chunk 1: Shared SessionDetector and PMF Tuning

### Task 1: Create SessionDetector concern with tests

**Files:**
- Create: `app/services/concerns/session_detector.rb`
- Create: `spec/services/concerns/session_detector_spec.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/services/concerns/session_detector_spec.rb
# frozen_string_literal: true

require 'rails_helper'

# Test harness: include the concern in a plain class
class SessionDetectorTestHarness
  include SessionDetector
end

RSpec.describe SessionDetector do
  subject(:detector) { SessionDetectorTestHarness.new }

  let(:time_regimes) do
    {
      open_expansion: { start: '09:15', end: '09:45' },
      trend_continuation: { start: '09:45', end: '11:30' },
      chop_decay: { start: '11:30', end: '13:45' },
      close_gamma: { start: '13:45', end: '15:15' }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: { time_regimes: time_regimes }
    })
  end

  context 'during open_expansion (09:30 IST)' do
    before do
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 09:30:00 +05:30'))
    end

    it 'returns :open_expansion' do
      expect(detector.detect_current_session).to eq(:open_expansion)
    end
  end

  context 'during chop_decay (12:00 IST)' do
    before do
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 12:00:00 +05:30'))
    end

    it 'returns :chop_decay' do
      expect(detector.detect_current_session).to eq(:chop_decay)
    end
  end

  context 'during close_gamma (14:00 IST)' do
    before do
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 14:00:00 +05:30'))
    end

    it 'returns :close_gamma' do
      expect(detector.detect_current_session).to eq(:close_gamma)
    end
  end

  context 'outside all sessions (08:00 IST)' do
    before do
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 08:00:00 +05:30'))
    end

    it 'returns nil' do
      expect(detector.detect_current_session).to be_nil
    end
  end

  context 'when time_regimes config is missing' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({ risk: {} })
    end

    it 'returns nil' do
      expect(detector.detect_current_session).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/concerns/session_detector_spec.rb`
Expected: FAIL — `SessionDetector` not found

- [ ] **Step 3: Implement SessionDetector concern**

```ruby
# app/services/concerns/session_detector.rb
# frozen_string_literal: true

# Shared session detection from risk.time_regimes config.
# Compares current IST time against configured session boundaries.
module SessionDetector
  def detect_current_session
    time_regimes = AlgoConfig.fetch.dig(:risk, :time_regimes)
    return nil unless time_regimes.is_a?(Hash)

    now = Time.current.in_time_zone('Asia/Kolkata')
    current_hhmm = now.strftime('%H:%M')

    time_regimes.each do |name, cfg|
      next unless cfg.is_a?(Hash)

      start_time = cfg[:start] || cfg['start']
      end_time = cfg[:end] || cfg['end']
      next unless start_time && end_time

      return name.to_sym if current_hhmm >= start_time.to_s && current_hhmm < end_time.to_s
    end

    nil
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/concerns/session_detector_spec.rb`
Expected: 5 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/services/concerns/session_detector.rb spec/services/concerns/session_detector_spec.rb
git commit -m "feat: extract SessionDetector concern for shared session detection"
```

---

### Task 2: Wire SessionDetector into EntryQualityFilter (replace duplicate)

**Files:**
- Modify: `app/services/signal/entry_quality_filter.rb:83-121` (replace private `detect_current_session`)
- Test: `spec/services/signal/entry_quality_filter_spec.rb` (existing tests should still pass)

- [ ] **Step 1: Run existing tests to confirm baseline**

Run: `bundle exec rspec spec/services/signal/entry_quality_filter_spec.rb`
Expected: All pass (baseline)

- [ ] **Step 2: Replace private method with concern include**

In `app/services/signal/entry_quality_filter.rb`, inside the `class << self` block (after line 24), add the include:

```ruby
    class << self
      include SessionDetector
```

Then delete the private `detect_current_session` method (lines 103-121 of the current file — the method body that starts with `time_regimes = AlgoConfig.fetch.dig(:risk, :time_regimes)` and ends with `nil`).

- [ ] **Step 3: Run tests to verify they still pass**

Run: `bundle exec rspec spec/services/signal/entry_quality_filter_spec.rb`
Expected: All pass (no behavior change)

- [ ] **Step 4: Commit**

```bash
git add app/services/signal/entry_quality_filter.rb
git commit -m "refactor: use shared SessionDetector in EntryQualityFilter"
```

---

### Task 3: Add PMF config to algo.yml

**Files:**
- Modify: `config/algo.yml:225-232` (after `structure_invalidation` section, before `# Time Stop`)
- Modify: `config/profiles/exit_testing.yml`

- [ ] **Step 1: Add PMF config section to algo.yml**

Insert after the `structure_invalidation` block (after line 232, before the `# Time Stop` comment at line 234). Use 4-space indent for `premium_momentum_failure:` to nest under `exits:` (the `# Time Stop` comment on the next line is at 2-space indent — a sibling of `exits:`, not a child):

```yaml
    premium_momentum_failure:
      enabled: true
      default_stall_minutes: 3
      index_overrides:
        SENSEX:
          stall_minutes: 4
      session_overrides:
        chop_decay:
          stall_minutes_add: 2
        close_gamma:
          stall_minutes_add: 2
```

- [ ] **Step 2: Add PMF config to exit_testing.yml**

Insert within the existing `risk:` block in `config/profiles/exit_testing.yml` (after line 34, after `pause_duration_minutes: 30`, before the `trade_limits:` block at line 36). Use 2-space indent for `exits:` to nest under `risk:`, 4-space for children:

```yaml
  exits:
    premium_momentum_failure:
      enabled: true
      default_stall_minutes: 2
      session_overrides:
        chop_decay:
          stall_minutes_add: 1
        close_gamma:
          stall_minutes_add: 1
```

**IMPORTANT:** Do NOT append to end of file — `exits:` must be inside the `risk:` block (lines 22-34), not after `entry_quality:` (line 40+).

- [ ] **Step 3: Commit**

```bash
git add config/algo.yml config/profiles/exit_testing.yml
git commit -m "chore: add PMF stall window config with index+session overrides"
```

---

### Task 4: Make PremiumMomentumFailureRule config-driven with tests

**Files:**
- Modify: `app/services/risk/rules/premium_momentum_failure_rule.rb:27-80`
- Create: `spec/services/risk/rules/premium_momentum_failure_rule_spec.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/services/risk/rules/premium_momentum_failure_rule_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::PremiumMomentumFailureRule do
  subject(:rule) { described_class.new(config: { enabled: true }) }

  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 1,
      created_at: 10.minutes.ago,
      entry_price: 200.0,
      meta: {
        'index_key' => index_key,
        'peak_premium' => 200.0,
        'peak_premium_at' => peak_at.iso8601
      }
    )
  end

  let(:position_data) do
    OpenStruct.new(current_ltp: 190.0) # Below peak, losing
  end

  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      tracker: tracker,
      position: position_data,
      active?: true,
      pnl_pct: -0.05 # Losing position
    )
  end

  let(:pmf_config) do
    {
      enabled: true,
      default_stall_minutes: 3,
      index_overrides: {
        SENSEX: { stall_minutes: 4 }
      },
      session_overrides: {
        chop_decay: { stall_minutes_add: 2 },
        close_gamma: { stall_minutes_add: 2 }
      }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        exits: { premium_momentum_failure: pmf_config },
        time_regimes: {
          open_expansion: { start: '09:15', end: '09:45' },
          trend_continuation: { start: '09:45', end: '11:30' },
          chop_decay: { start: '11:30', end: '13:45' },
          close_gamma: { start: '13:45', end: '15:15' }
        }
      }
    })
  end

  describe 'index-aware stall minutes' do
    let(:index_key) { 'NIFTY' }
    let(:peak_at) { 4.minutes.ago } # 4 min since peak

    context 'NIFTY in morning (default 3 min) — stalled 4 min' do
      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 10:00:00 +05:30'))
      end

      it 'triggers PMF exit (4 >= 3)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('PREMIUM_MOMENTUM_FAILURE')
      end
    end

    context 'SENSEX in morning (base 4 min) — stalled 3.5 min' do
      let(:index_key) { 'SENSEX' }
      let(:peak_at) { 3.5.minutes.ago }

      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 10:00:00 +05:30'))
      end

      it 'does NOT trigger PMF (3.5 < 4)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end
  end

  describe 'session-aware stall minutes' do
    let(:index_key) { 'NIFTY' }

    context 'NIFTY in chop_decay (3 + 2 = 5 min) — stalled 4 min' do
      let(:peak_at) { 4.minutes.ago }

      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 12:00:00 +05:30'))
      end

      it 'does NOT trigger PMF (4 < 5)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end

    context 'SENSEX in chop_decay (4 + 2 = 6 min) — stalled 6 min' do
      let(:index_key) { 'SENSEX' }
      let(:peak_at) { 6.minutes.ago }

      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 12:00:00 +05:30'))
      end

      it 'triggers PMF exit (6 >= 6)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'NIFTY in close_gamma (3 + 2 = 5 min) — stalled 5 min' do
      let(:peak_at) { 5.minutes.ago }

      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 14:00:00 +05:30'))
      end

      it 'triggers PMF exit (5 >= 5)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end
  end

  describe 'fallback when config absent' do
    let(:index_key) { 'NIFTY' }
    let(:peak_at) { 3.minutes.ago }

    before do
      allow(AlgoConfig).to receive(:fetch).and_return({ risk: {} })
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 10:00:00 +05:30'))
    end

    it 'falls back to DEFAULT_STALL_MINUTES (3)' do
      result = rule.evaluate(context)
      expect(result.exit?).to be true
    end
  end

  describe 'winning position is skipped' do
    let(:index_key) { 'NIFTY' }
    let(:peak_at) { 5.minutes.ago }

    before do
      allow(context).to receive(:pnl_pct).and_return(0.05) # Winning
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-17 10:00:00 +05:30'))
    end

    it 'returns no_action (winners handled by trailing)' do
      result = rule.evaluate(context)
      expect(result.exit?).to be false
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/risk/rules/premium_momentum_failure_rule_spec.rb`
Expected: Some tests fail (SENSEX morning should NOT trigger at 3.5 min but currently does with hardcoded 3)

- [ ] **Step 3: Implement config-driven stall resolution**

Replace the full content of `app/services/risk/rules/premium_momentum_failure_rule.rb`:

```ruby
# frozen_string_literal: true

module Risk
  module Rules
    # Premium Momentum Failure Rule - CRITICAL EXIT for intraday options buying
    #
    # PURPOSE: Kill dead option trades before theta eats them
    #
    # Logic: Track last premium high. Exit when premium does NOT make
    # progress within N minutes (configurable per index and session).
    #
    # Only fires on losing positions. Winners are handled by trailing.
    #
    # Priority: 30 (checked after structure invalidation)
    class PremiumMomentumFailureRule < BaseRule
      include SessionDetector

      PRIORITY = 30
      DEFAULT_STALL_MINUTES = 3

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        tracker = context.tracker
        return skip_result unless tracker.created_at

        current_ltp = context.position.respond_to?(:current_ltp) ? context.position.current_ltp.to_f : nil
        current_ltp ||= tracker.entry_price.to_f

        meta = tracker.meta || {}
        peak = meta['peak_premium'].to_f
        last_peak_at = meta['peak_premium_at'] ? Time.zone.parse(meta['peak_premium_at']) : tracker.created_at

        if current_ltp > peak
          meta['peak_premium'] = current_ltp
          meta['peak_premium_at'] = Time.current.iso8601
          tracker.update_column(:meta, meta) # rubocop:disable Rails/SkipsModelValidations
          return no_action_result
        end

        return no_action_result if context.pnl_pct.to_f.positive?

        stall_minutes = resolve_stall_minutes(tracker)
        elapsed_since_peak = (Time.current - last_peak_at) / 60.0

        if elapsed_since_peak >= stall_minutes
          reason = "PREMIUM_MOMENTUM_FAILURE (No new peak in #{elapsed_since_peak.round(1)} mins, Peak: #{peak.round(2)})"
          return exit_result(
            reason: reason,
            metadata: {
              peak: peak,
              current: current_ltp,
              elapsed_since_peak: elapsed_since_peak,
              stall_threshold: stall_minutes
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[PremiumMomentumFailureRule] Error: #{e.class} - #{e.message}")
        skip_result
      end

      private

      def resolve_stall_minutes(tracker)
        pmf_cfg = AlgoConfig.fetch.dig(:risk, :exits, :premium_momentum_failure) || {}

        index_key = tracker.meta&.dig('index_key')
        base = if index_key
                 pmf_cfg.dig(:index_overrides, index_key.to_sym, :stall_minutes) ||
                   pmf_cfg[:default_stall_minutes] || DEFAULT_STALL_MINUTES
               else
                 pmf_cfg[:default_stall_minutes] || DEFAULT_STALL_MINUTES
               end

        session = detect_current_session
        additive = session ? (pmf_cfg.dig(:session_overrides, session, :stall_minutes_add) || 0) : 0

        (base.to_f + additive.to_f).to_i
      rescue StandardError
        DEFAULT_STALL_MINUTES
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/risk/rules/premium_momentum_failure_rule_spec.rb`
Expected: All pass

- [ ] **Step 5: Run rubocop on modified files**

Run: `bundle exec rubocop app/services/risk/rules/premium_momentum_failure_rule.rb`
Expected: No offenses

- [ ] **Step 6: Commit**

```bash
git add app/services/risk/rules/premium_momentum_failure_rule.rb spec/services/risk/rules/premium_momentum_failure_rule_spec.rb
git commit -m "feat: config-driven PMF stall minutes with index+session awareness

NIFTY: 3 min base, SENSEX: 4 min base.
chop_decay/close_gamma add +2 min.
Falls back to DEFAULT_STALL_MINUTES (3) when config absent."
```

---

## Chunk 2: PREMIUM_R_STOP Suppression

### Task 5: Suppress PREMIUM_R_STOP when trailing is armed

**Files:**
- Modify: `app/services/live/risk_manager_service/exit_enforcement.rb:326-345`
- Create: `spec/services/live/risk_manager_service/exit_enforcement_spec.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/services/live/risk_manager_service/exit_enforcement_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService::ExitEnforcement do
  # Test harness: include the module in a plain class
  let(:harness) do
    Class.new do
      include Live::RiskManagerService::ExitEnforcement
    end.new
  end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          trailing: { enabled: true, activation_pct: 0.025 }
        }
      })
    end

    context 'when peak profit exceeds trailing activation' do
      let(:tracker) do
        instance_double(PositionTracker, entry_price: 100.0, quantity: 100)
      end
      let(:snapshot) { { hwm_pnl: 500.0 } } # 500 / 10000 = 5% > 2.5%

      it 'returns true' do
        expect(harness.send(:trailing_armed_for?, tracker, snapshot)).to be true
      end
    end

    context 'when peak profit is below trailing activation' do
      let(:tracker) do
        instance_double(PositionTracker, entry_price: 100.0, quantity: 100)
      end
      let(:snapshot) { { hwm_pnl: 100.0 } } # 100 / 10000 = 1% < 2.5%

      it 'returns false' do
        expect(harness.send(:trailing_armed_for?, tracker, snapshot)).to be false
      end
    end

    context 'when trailing is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: { trailing: { enabled: false, activation_pct: 0.025 } }
        })
      end

      let(:tracker) do
        instance_double(PositionTracker, entry_price: 100.0, quantity: 100)
      end
      let(:snapshot) { { hwm_pnl: 500.0 } }

      it 'returns false' do
        expect(harness.send(:trailing_armed_for?, tracker, snapshot)).to be false
      end
    end

    context 'when entry value is zero' do
      let(:tracker) do
        instance_double(PositionTracker, entry_price: 0.0, quantity: 0)
      end
      let(:snapshot) { { hwm_pnl: 500.0 } }

      it 'returns false (safe default)' do
        expect(harness.send(:trailing_armed_for?, tracker, snapshot)).to be false
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/live/risk_manager_service/exit_enforcement_spec.rb`
Expected: FAIL — `trailing_armed_for?` method not found

- [ ] **Step 3: Implement trailing_armed_for? and R-stop suppression**

In `app/services/live/risk_manager_service/exit_enforcement.rb`, modify `enforce_premium_r_stop_for` (lines 326-345):

```ruby
      def enforce_premium_r_stop_for(tracker, exit_engine:)
        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        # Skip R-stop when trailing system has taken ownership
        if trailing_armed_for?(tracker, snapshot)
          Rails.logger.debug do
            "[RiskManager] PREMIUM_R_STOP suppressed for #{tracker.order_no} — trailing armed"
          end
          return
        end

        ltp = snapshot[:ltp]
        return unless ltp

        premium_stop = tracker.meta&.dig('premium_stop_price')
        return unless premium_stop

        if ltp.to_f <= premium_stop.to_f
          reason = "PREMIUM_R_STOP (ltp: #{ltp}, stop: #{premium_stop})"
          exit_path = 'premium_r_stop'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_premium_r_stop_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end
```

Add the private method (after `options_structure_invalidated_enforcement?`, before `# LAYER 3: PREMIUM MOMENTUM FAILURE`):

```ruby
      def trailing_armed_for?(tracker, snapshot)
        trailing_cfg = AlgoConfig.fetch.dig(:risk, :trailing) || {}
        return false if trailing_cfg[:enabled] == false

        activation = (trailing_cfg[:activation_pct] || 0.025).to_f
        return false unless activation.positive?

        entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
        return false unless entry_value.positive?

        peak_profit_pct = snapshot[:hwm_pnl].to_f / entry_value
        peak_profit_pct >= activation
      rescue StandardError
        false
      end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/live/risk_manager_service/exit_enforcement_spec.rb`
Expected: All pass

- [ ] **Step 5: Run rubocop**

Run: `bundle exec rubocop app/services/live/risk_manager_service/exit_enforcement.rb`
Expected: No offenses

- [ ] **Step 6: Commit**

```bash
git add app/services/live/risk_manager_service/exit_enforcement.rb spec/services/live/risk_manager_service/exit_enforcement_spec.rb
git commit -m "feat: suppress PREMIUM_R_STOP when trailing is armed

When peak profit reaches trailing activation (2.5%), skip the hard
premium R-stop. The trailing system owns exit management. R-stop
resumes if profit drops below activation (trailing disarms)."
```

---

### Task 6: Final verification

**Files:** All modified files

- [ ] **Step 1: Run all related specs**

Run: `bundle exec rspec spec/services/concerns/session_detector_spec.rb spec/services/risk/rules/premium_momentum_failure_rule_spec.rb spec/services/live/risk_manager_service/exit_enforcement_spec.rb spec/services/signal/entry_quality_filter_spec.rb`
Expected: All pass

- [ ] **Step 2: Run rubocop on all modified files**

Run: `bundle exec rubocop app/services/concerns/session_detector.rb app/services/risk/rules/premium_momentum_failure_rule.rb app/services/live/risk_manager_service/exit_enforcement.rb app/services/signal/entry_quality_filter.rb`
Expected: No offenses

- [ ] **Step 3: Verify config loads correctly**

Run: `bundle exec rails runner "puts AlgoConfig.fetch.dig(:risk, :exits, :premium_momentum_failure).inspect"`
Expected: Hash with `default_stall_minutes`, `index_overrides`, `session_overrides`

- [ ] **Step 4: Review git log**

Run: `git log --oneline -6`
Expected: Clean commit history with all tasks
