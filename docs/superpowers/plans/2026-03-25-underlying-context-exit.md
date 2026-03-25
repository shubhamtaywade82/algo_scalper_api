# Underlying-Context-Aware Trailing Exit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `Live::UnderlyingMonitor` signals into the tick-first trailing path so BOS breaks trigger immediate exits and trend weakness tightens the trailing buffer in real time.

**Architecture:** A new `Live::UnderlyingContextEvaluator` module is included into `UnifiedExitChecker`'s singleton. It calls `UnderlyingMonitor.evaluate` (already cached at 250ms) only when trailing is armed, and returns `{ action:, multiplier:, reason: }`. The trailing section of `check_exit_conditions` branches on `:exit` and passes `multiplier` into `adaptive_trailing_exit?` which compresses `allowed_dd`.

**Tech Stack:** Ruby 3.3.4, Rails 8, RSpec, `Positions::ActiveCache`, `Live::UnderlyingMonitor`, `Positions::TrailingConfig`

**Spec:** `docs/superpowers/specs/2026-03-25-underlying-context-exit-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| CREATE | `app/services/live/underlying_context_evaluator.rb` | Reads `UnderlyingMonitor` state, returns `{ action:, multiplier:, reason: }` |
| MODIFY | `app/services/live/unified_exit_checker.rb` | Include module; replace trailing call site; add `tightening_multiplier:` to two methods |
| MODIFY | `config/algo.yml` | Add `risk.underlying_context_exit` config block |
| CREATE | `spec/services/live/underlying_context_evaluator_spec.rb` | Unit tests for the new module in isolation |
| MODIFY | `spec/services/live/unified_exit_checker_spec.rb` | Integration tests for the wired-in behaviour |

---

## Task 1: Add config block to `algo.yml`

**Files:**
- Modify: `config/algo.yml`

- [ ] **Step 1: Add the config block**

Find the `risk:` section in `config/algo.yml` (search for `percentage_pnl_exit:`). Insert the new block directly after it:

```yaml
  # Underlying-context-aware trailing exit (tick-first path)
  # Tightens or forces trailing exit when underlying structure/trend signals reversal.
  # Only active when trailing is already armed (position profitable >= activation_pct).
  underlying_context_exit:
    enabled: true
    trend_score_threshold: 15     # trend_score below this = weak trend
    atr_ratio_threshold: 0.65     # atr_ratio below this AND falling = collapsing
    tightening_multiplier: 0.5    # compress allowed_dd by this factor when weakening
```

- [ ] **Step 2: Verify YAML parses cleanly**

```bash
bundle exec ruby -e "require 'yaml'; puts YAML.load_file('config/algo.yml').dig(:risk, 'underlying_context_exit').inspect"
```

If that returns nil (symbol vs string key), try:
```bash
bundle exec rails runner "puts AlgoConfig.fetch.dig(:risk, :underlying_context_exit).inspect"
```

Expected: `{enabled: true, trend_score_threshold: 15, atr_ratio_threshold: 0.65, tightening_multiplier: 0.5}`

- [ ] **Step 3: Commit**

```bash
git add config/algo.yml
git commit -m "config: add risk.underlying_context_exit block for underlying-aware trailing"
```

---

## Task 2: Create `UnderlyingContextEvaluator` — failing tests first

**Files:**
- Create: `spec/services/live/underlying_context_evaluator_spec.rb`

- [ ] **Step 1: Create the spec file**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::UnderlyingContextEvaluator do
  # Include the module into a test host that mimics UnifiedExitChecker's singleton shape
  let(:host) do
    host_class = Class.new do
      class << self
        include Live::UnderlyingContextEvaluator

        # Stub trailing_armed? (the module calls this from exit_config)
        def exit_config
          {
            trailing: { enabled: true, type: 'adaptive', activation_profit: 0.10,
                        drop_threshold: 0.05 }
          }
        end
      end
    end
    host_class
  end

  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 42,
      entry_price: 276.65,
      quantity: 100,
      symbol: 'SENSEX-Mar2026-75000-CE',
      order_no: 'ORD-TEST',
      meta: { 'index_key' => 'sensex', 'direction' => 'long_ce' }
    )
  end

  # snapshot where trailing IS armed: hwm_pnl >> entry_value * activation (0.10)
  # entry_value = 276.65 * 100 = 27_665; activation = 10% = 2_766.5
  # hwm = 39_215 > 2_766.5 → armed
  let(:snapshot_armed)     { { pnl_pct: 1.4182, ltp: 669.0, pnl: 39_215.0, hwm_pnl: 39_215.0 } }
  # snapshot where trailing is NOT armed: hwm_pnl = 0
  let(:snapshot_not_armed) { { pnl_pct: 0.05, ltp: 290.0, pnl: 1_335.0, hwm_pnl: 0.0 } }

  let(:healthy_state) do
    OpenStruct.new(
      trend_score: 45.0,
      bos_state: :intact,
      bos_direction: :neutral,
      atr_trend: :flat,
      atr_ratio: 0.95,
      mtf_confirm: true,
      ltp: 79_500.0,
      smc_bias_flip: false
    )
  end

  let(:bos_break_against_long) do
    OpenStruct.new(
      trend_score: 20.0,
      bos_state: :broken,
      bos_direction: :bearish,   # bearish BOS breaks long_ce thesis
      atr_trend: :rising,
      atr_ratio: 1.1,
      mtf_confirm: false,
      ltp: 78_200.0,
      smc_bias_flip: false
    )
  end

  let(:weak_trend_state) do
    OpenStruct.new(
      trend_score: 10.0,           # below threshold of 15
      bos_state: :intact,
      bos_direction: :neutral,
      atr_trend: :flat,
      atr_ratio: 0.80,
      mtf_confirm: false,
      ltp: 79_000.0,
      smc_bias_flip: false
    )
  end

  let(:atr_collapse_state) do
    OpenStruct.new(
      trend_score: 25.0,           # healthy score
      bos_state: :intact,
      bos_direction: :neutral,
      atr_trend: :falling,
      atr_ratio: 0.55,             # below threshold of 0.65
      mtf_confirm: true,
      ltp: 79_200.0,
      smc_bias_flip: false
    )
  end

  let(:dual_weakness_state) do
    OpenStruct.new(
      trend_score: 8.0,            # weak
      bos_state: :intact,
      bos_direction: :neutral,
      atr_trend: :falling,
      atr_ratio: 0.50,             # collapsing
      mtf_confirm: false,
      ltp: 78_800.0,
      smc_bias_flip: false
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        underlying_context_exit: {
          enabled: true,
          trend_score_threshold: 15,
          atr_ratio_threshold: 0.65,
          tightening_multiplier: 0.5
        }
      }
    })
    # Default: return healthy state unless overridden in individual contexts
    allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(healthy_state)
    # Default: ActiveCache returns nil (simulate missing pos_data gracefully)
    allow(Positions::ActiveCache.instance).to receive(:get_by_tracker_id).and_return(nil)
  end

  describe '#evaluate_underlying_context' do
    context 'when trailing is NOT armed (hwm_pnl = 0)' do
      it 'returns :hold with multiplier 1.0 without calling UnderlyingMonitor' do
        result = host.evaluate_underlying_context(tracker, snapshot_not_armed)
        expect(result).to eq({ action: :hold, multiplier: 1.0, reason: nil })
        expect(Live::UnderlyingMonitor).not_to have_received(:evaluate)
      end
    end

    context 'when underlying_context_exit is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: { underlying_context_exit: { enabled: false } }
        })
      end

      it 'returns :hold with multiplier 1.0' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result).to eq({ action: :hold, multiplier: 1.0, reason: nil })
      end
    end

    context 'when UnderlyingMonitor returns nil / raises' do
      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(nil) }

      it 'returns :hold with multiplier 1.0' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result).to eq({ action: :hold, multiplier: 1.0, reason: nil })
      end
    end

    context 'when underlying is healthy' do
      it 'returns :hold with multiplier 1.0' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result).to eq({ action: :hold, multiplier: 1.0, reason: nil })
      end
    end

    context 'when BOS breaks against a long_ce position (bearish BOS)' do
      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(bos_break_against_long) }

      it 'returns :exit with UNDERLYING_STRUCTURE_BREAK reason' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:exit)
        expect(result[:reason]).to include('UNDERLYING_STRUCTURE_BREAK')
        expect(result[:multiplier]).to be_nil.or be_a(Numeric) # multiplier irrelevant on :exit
      end
    end

    context 'when BOS breaks against a long_pe position (bullish BOS)' do
      let(:pe_tracker) do
        instance_double(
          PositionTracker,
          id: 43,
          entry_price: 200.0,
          quantity: 50,
          symbol: 'SENSEX-Mar2026-74000-PE',
          order_no: 'ORD-PE',
          meta: { 'index_key' => 'sensex', 'direction' => 'long_pe' }
        )
      end

      let(:bos_break_against_short) do
        OpenStruct.new(
          trend_score: 20.0,
          bos_state: :broken,
          bos_direction: :bullish,  # bullish BOS breaks long_pe thesis
          atr_trend: :rising,
          atr_ratio: 1.1,
          mtf_confirm: false,
          ltp: 80_000.0,
          smc_bias_flip: false
        )
      end

      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(bos_break_against_short) }

      it 'returns :exit with UNDERLYING_STRUCTURE_BREAK reason' do
        result = host.evaluate_underlying_context(pe_tracker, snapshot_armed)
        expect(result[:action]).to eq(:exit)
        expect(result[:reason]).to include('UNDERLYING_STRUCTURE_BREAK')
      end
    end

    context 'when trend is weak AND ATR is collapsing (dual weakness)' do
      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(dual_weakness_state) }

      it 'returns :exit with UNDERLYING_DUAL_WEAKNESS reason' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:exit)
        expect(result[:reason]).to include('UNDERLYING_DUAL_WEAKNESS')
      end
    end

    context 'when trend is weak but ATR is healthy' do
      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(weak_trend_state) }

      it 'returns :tighten with configured multiplier (0.5)' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:tighten)
        expect(result[:multiplier]).to eq(0.5)
        expect(result[:reason]).to include('UNDERLYING_WEAKENING')
      end
    end

    context 'when ATR is collapsing but trend score is healthy' do
      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(atr_collapse_state) }

      it 'returns :tighten with configured multiplier (0.5)' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:tighten)
        expect(result[:multiplier]).to eq(0.5)
        expect(result[:reason]).to include('UNDERLYING_WEAKENING')
      end
    end

    context 'when smc_bias_flip is true but no other weakness' do
      before do
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(
          OpenStruct.new(
            trend_score: 40.0, bos_state: :intact, bos_direction: :neutral,
            atr_trend: :flat, atr_ratio: 0.90, mtf_confirm: true,
            ltp: 79_500.0, smc_bias_flip: true
          )
        )
      end

      it 'returns :hold — smc_bias_flip is excluded from this evaluator' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:hold)
      end
    end

    context 'multiplier is always a Float, never nil' do
      it 'hold path returns Float multiplier' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:multiplier]).to be_a(Float)
      end

      it 'not-armed path returns Float multiplier' do
        result = host.evaluate_underlying_context(tracker, snapshot_not_armed)
        expect(result[:multiplier]).to be_a(Float)
      end

      it 'tighten path returns Float multiplier' do
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(weak_trend_state)
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:multiplier]).to be_a(Float)
      end
    end

    context 'with configurable thresholds' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            underlying_context_exit: {
              enabled: true,
              trend_score_threshold: 25,   # higher threshold
              atr_ratio_threshold: 0.65,
              tightening_multiplier: 0.3
            }
          }
        })
        # trend_score: 10 < 25 (new threshold) → weak
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(weak_trend_state)
      end

      it 'uses the configured trend_score_threshold' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:tighten)
        expect(result[:multiplier]).to eq(0.3)
      end
    end
  end
end
```

- [ ] **Step 2: Run spec — expect it to fail with `NameError: uninitialized constant Live::UnderlyingContextEvaluator`**

```bash
bundle exec rspec spec/services/live/underlying_context_evaluator_spec.rb --format documentation 2>&1 | head -20
```

Expected: `NameError` or `LoadError` — the module doesn't exist yet.

---

## Task 3: Implement `UnderlyingContextEvaluator`

**Files:**
- Create: `app/services/live/underlying_context_evaluator.rb`

- [ ] **Step 1: Create the module**

```ruby
# frozen_string_literal: true

module Live
  # Evaluates underlying index state to inform trailing stop behaviour.
  # Included into Live::UnifiedExitChecker's singleton class.
  #
  # Returns { action: :exit | :tighten | :hold, multiplier: Float, reason: String | nil }
  # Only evaluates when trailing is already armed (position is profitable enough).
  #
  # :exit     — BOS broken against position, or dual weakness (trend + ATR)
  # :tighten  — single weakness signal; caller compresses allowed_dd by multiplier
  # :hold     — underlying healthy or data unavailable; trailing unchanged
  module UnderlyingContextEvaluator
    private

    def evaluate_underlying_context(tracker, snapshot)
      cfg = underlying_context_cfg
      return hold_result unless cfg[:enabled]
      return hold_result unless trailing_armed?(tracker, snapshot, exit_config)

      pos_data = Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
      underlying_pd = build_underlying_position_data(tracker, pos_data)
      state = Live::UnderlyingMonitor.evaluate(underlying_pd)
      return hold_result unless state

      direction = resolve_position_direction(tracker, pos_data)

      if bos_broken_against?(state, direction)
        return exit_result("UNDERLYING_STRUCTURE_BREAK (BOS #{state.bos_direction}, " \
                           "tracker=#{tracker.order_no})")
      end

      weak   = trend_weak?(state, cfg)
      collap = atr_collapsing?(state, cfg)

      if weak && collap
        return exit_result("UNDERLYING_DUAL_WEAKNESS (trend_score=#{state.trend_score&.round(1)}, " \
                           "atr_ratio=#{state.atr_ratio&.round(3)}, tracker=#{tracker.order_no})")
      end

      if weak || collap
        signal = weak ? "trend_score=#{state.trend_score&.round(1)}" : "atr_ratio=#{state.atr_ratio&.round(3)}"
        return tighten_result("UNDERLYING_WEAKENING (#{signal}, tracker=#{tracker.order_no})",
                              multiplier: cfg[:tightening_multiplier].to_f)
      end

      hold_result
    rescue StandardError => e
      Rails.logger.error("[UnderlyingContextEvaluator] evaluate failed: #{e.class} - #{e.message}")
      hold_result
    end

    # Build the position_data OpenStruct that UnderlyingMonitor.evaluate expects.
    # Reads underlying_segment and underlying_security_id from ActiveCache pos_data
    # (already populated by Positions::MetadataResolver at entry time).
    def build_underlying_position_data(tracker, pos_data)
      index_key = tracker.meta&.dig('index_key')

      OpenStruct.new(
        tracker_id:             tracker.id,
        index_key:              index_key,
        underlying_symbol:      index_key,            # fallback in UnderlyingMonitor#determine_index_cfg
        underlying_segment:     pos_data&.underlying_segment,
        underlying_security_id: pos_data&.underlying_security_id,
        position_direction:     resolve_position_direction(tracker, pos_data),
        underlying_ltp:         nil                   # UnderlyingMonitor fetches via TickQuery
      )
    end

    # Normalise raw direction value to :bullish / :bearish.
    # UnderlyingMonitor#structure_state only handles these two symbols.
    # Safe default: :bullish — unknown direction → false negative, never false positive.
    def resolve_position_direction(tracker, pos_data)
      raw = pos_data&.position_direction.presence ||
            tracker.meta&.dig('direction').presence

      case raw.to_s.downcase
      when 'long_pe', 'bearish', 'put' then :bearish
      when 'long_ce', 'bullish', 'call' then :bullish
      else :bullish
      end
    end

    def bos_broken_against?(state, direction)
      return false unless state.bos_state == :broken

      (direction == :bullish && state.bos_direction == :bearish) ||
        (direction == :bearish && state.bos_direction == :bullish)
    end

    def trend_weak?(state, cfg)
      return false unless state.trend_score

      state.trend_score.to_f < cfg[:trend_score_threshold].to_f
    end

    def atr_collapsing?(state, cfg)
      state.atr_trend == :falling &&
        state.atr_ratio &&
        state.atr_ratio.to_f < cfg[:atr_ratio_threshold].to_f
    end

    def underlying_context_cfg
      cfg = AlgoConfig.fetch.dig(:risk, :underlying_context_exit) || {}
      {
        enabled:               cfg.fetch(:enabled, true),
        trend_score_threshold: cfg.fetch(:trend_score_threshold, 15).to_f,
        atr_ratio_threshold:   cfg.fetch(:atr_ratio_threshold, 0.65).to_f,
        tightening_multiplier: cfg.fetch(:tightening_multiplier, 0.5).to_f
      }
    rescue StandardError
      { enabled: false, trend_score_threshold: 15.0, atr_ratio_threshold: 0.65,
        tightening_multiplier: 0.5 }
    end

    def hold_result
      { action: :hold, multiplier: 1.0, reason: nil }
    end

    def tighten_result(reason, multiplier:)
      { action: :tighten, multiplier: multiplier.to_f, reason: reason }
    end

    def exit_result(reason)
      { action: :exit, multiplier: 1.0, reason: reason }
    end
  end
end
```

- [ ] **Step 2: Run the spec**

```bash
bundle exec rspec spec/services/live/underlying_context_evaluator_spec.rb --format documentation 2>&1 | tail -30
```

Expected: all examples pass.

- [ ] **Step 3: Commit**

```bash
git add app/services/live/underlying_context_evaluator.rb \
        spec/services/live/underlying_context_evaluator_spec.rb
git commit -m "feat: add Live::UnderlyingContextEvaluator module with full test coverage"
```

---

## Task 4: Extend `adaptive_trailing_exit?` to accept `tightening_multiplier:`

**Files:**
- Modify: `app/services/live/unified_exit_checker.rb` (lines 666–690)

- [ ] **Step 1: Write the failing test first**

In `spec/services/live/unified_exit_checker_spec.rb`, add inside `RSpec.describe Live::UnifiedExitChecker do` (before the final `end`):

```ruby
describe '#adaptive_trailing_exit? with tightening_multiplier' do
  let(:tiers) { [{ min_profit: 0.15, drawdown: 0.06 }] }
  # peak_profit_pct = 1.4182 (141.82%), hwm = 39_215, entry_value = 27_665
  # Normal trigger: (hwm - pnl) / hwm * 1.4182 >= 0.06 → needs 4.23% drop
  # Tightened (0.5x): needs 2.12% drop

  let(:snapshot_at_hwm)      { { hwm_pnl: 39_215.0, pnl: 39_215.0 } }
  let(:snapshot_2pct_drop)   { { hwm_pnl: 39_215.0, pnl: 38_430.0 } }  # ~2% drop from hwm
  let(:snapshot_45pct_drop)  { { hwm_pnl: 39_215.0, pnl: 37_553.0 } }  # ~4.3% drop from hwm

  it 'does not fire at HWM with normal multiplier' do
    result = described_class.send(:adaptive_trailing_exit?, tracker, snapshot_at_hwm, 1.4182, tiers,
                                  tightening_multiplier: 1.0)
    expect(result).to be false
  end

  it 'does not fire at 2% drop with normal multiplier (needs 4.23%)' do
    result = described_class.send(:adaptive_trailing_exit?, tracker, snapshot_2pct_drop, 1.4182, tiers,
                                  tightening_multiplier: 1.0)
    expect(result).to be false
  end

  it 'fires at 4.3% drop with normal multiplier' do
    result = described_class.send(:adaptive_trailing_exit?, tracker, snapshot_45pct_drop, 1.4182, tiers,
                                  tightening_multiplier: 1.0)
    expect(result).to be true
  end

  it 'fires at 2% drop with tightening multiplier 0.5 (effective threshold 2.12%)' do
    result = described_class.send(:adaptive_trailing_exit?, tracker, snapshot_2pct_drop, 1.4182, tiers,
                                  tightening_multiplier: 0.5)
    expect(result).to be true
  end

  it 'does not fire at HWM even with tightening multiplier' do
    result = described_class.send(:adaptive_trailing_exit?, tracker, snapshot_at_hwm, 1.4182, tiers,
                                  tightening_multiplier: 0.5)
    expect(result).to be false
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rspec spec/services/live/unified_exit_checker_spec.rb \
  -e "adaptive_trailing_exit? with tightening_multiplier" --format documentation 2>&1
```

Expected: `ArgumentError: wrong number of arguments` or similar — method doesn't accept `tightening_multiplier:` yet.

- [ ] **Step 3: Update `adaptive_trailing_exit?` signature and logic**

In `app/services/live/unified_exit_checker.rb`, find line 666 and replace the method signature + comparison line:

Old (lines 666–676):
```ruby
      def adaptive_trailing_exit?(tracker, snapshot, peak_profit_pct, adaptive_tiers)
        allowed_dd = Positions::TrailingConfig.adaptive_drawdown_for_peak(peak_profit_pct, adaptive_tiers)
        return false unless allowed_dd && peak_profit_pct.positive?

        hwm = snapshot[:hwm_pnl].to_f
        pnl_value = snapshot[:pnl].to_f
        return false unless hwm.positive?

        # Convert fractional drop from HWM into profit-percent scale for comparison with allowed_dd
        drop_from_peak_pct = (hwm - pnl_value) / hwm * peak_profit_pct
        return false unless drop_from_peak_pct >= allowed_dd
```

New:
```ruby
      def adaptive_trailing_exit?(tracker, snapshot, peak_profit_pct, adaptive_tiers,
                                  tightening_multiplier: 1.0)
        allowed_dd = Positions::TrailingConfig.adaptive_drawdown_for_peak(peak_profit_pct, adaptive_tiers)
        return false unless allowed_dd && peak_profit_pct.positive?

        hwm = snapshot[:hwm_pnl].to_f
        pnl_value = snapshot[:pnl].to_f
        return false unless hwm.positive?

        # Apply underlying-context tightening: compress allowed_dd when trend/ATR weakening
        effective_allowed_dd = allowed_dd * tightening_multiplier.to_f

        # Convert fractional drop from HWM into profit-percent scale for comparison
        drop_from_peak_pct = (hwm - pnl_value) / hwm * peak_profit_pct
        return false unless drop_from_peak_pct >= effective_allowed_dd
```

- [ ] **Step 4: Run the new tests**

```bash
bundle exec rspec spec/services/live/unified_exit_checker_spec.rb \
  -e "adaptive_trailing_exit? with tightening_multiplier" --format documentation 2>&1
```

Expected: all 5 examples pass.

- [ ] **Step 5: Run the full spec to confirm no regression**

```bash
bundle exec rspec spec/services/live/unified_exit_checker_spec.rb --format documentation 2>&1 | tail -20
```

Expected: all examples pass.

- [ ] **Step 6: Commit**

```bash
git add app/services/live/unified_exit_checker.rb \
        spec/services/live/unified_exit_checker_spec.rb
git commit -m "feat: adaptive_trailing_exit? accepts tightening_multiplier kwarg"
```

---

## Task 5: Wire `evaluate_underlying_context` into `check_exit_conditions`

**Files:**
- Modify: `app/services/live/unified_exit_checker.rb` (three edits)

- [ ] **Step 1: Write the failing integration tests first**

Append to `spec/services/live/unified_exit_checker_spec.rb` (before the final `end`):

```ruby
describe 'underlying-context-aware trailing (integration)' do
  # SENSEX position at 141.82% profit — trailing armed (hwm > activation threshold)
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 99,
      active?: true,
      entry_price: 276.65,
      quantity: 100,
      high_water_mark_pnl: 39_215.0,
      current_pnl_pct: 1.4182,
      symbol: 'SENSEX-Mar2026-75000-CE',
      order_no: 'ORD-SENSEX',
      meta: { 'index_key' => 'sensex', 'direction' => 'long_ce' }
    )
  end

  let(:snapshot_at_hwm)    { { pnl_pct: 1.4182, ltp: 669.0, pnl: 39_215.0, hwm_pnl: 39_215.0 } }
  let(:snapshot_2pct_drop) { { pnl_pct: 1.38,   ltp: 655.0, pnl: 38_430.0, hwm_pnl: 39_215.0 } }
  let(:snapshot_5pct_drop) { { pnl_pct: 1.35,   ltp: 635.0, pnl: 37_260.0, hwm_pnl: 39_215.0 } }

  let(:healthy_state) do
    OpenStruct.new(trend_score: 45.0, bos_state: :intact, bos_direction: :neutral,
                   atr_trend: :flat, atr_ratio: 0.95, mtf_confirm: true,
                   ltp: 79_500.0, smc_bias_flip: false)
  end
  let(:bos_break_state) do
    OpenStruct.new(trend_score: 20.0, bos_state: :broken, bos_direction: :bearish,
                   atr_trend: :rising, atr_ratio: 1.1, mtf_confirm: false,
                   ltp: 78_200.0, smc_bias_flip: false)
  end
  let(:weak_trend_state) do
    OpenStruct.new(trend_score: 10.0, bos_state: :intact, bos_direction: :neutral,
                   atr_trend: :flat, atr_ratio: 0.80, mtf_confirm: false,
                   ltp: 79_000.0, smc_bias_flip: false)
  end

  before do
    allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(snapshot_at_hwm)
    allow(Positions::ActiveCache.instance).to receive(:get_by_tracker_id).and_return(nil)
    allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(healthy_state)
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        underlying_context_exit: { enabled: true, trend_score_threshold: 15,
                                   atr_ratio_threshold: 0.65, tightening_multiplier: 0.5 },
        institutional_trailing: {
          sensex: {
            activation_trigger: 0.15,
            trailing_distance: 0.15,
            adaptive_drawdown: [
              { min_profit: 0.15, drawdown: 0.10 },
              { min_profit: 0.50, drawdown: 0.06 },
              { min_profit: 1.00, drawdown: 0.03 }
            ]
          }
        },
        exits: {},
        percentage_pnl_exit: { enabled: false }
      },
      exit: {},
      position_sizing: { drawdown: { emergency_peak_loss_exit: false } }
    })
    allow(described_class).to receive_messages(
      portfolio_floor_breach?: false,
      early_exit_triggered?: false,
      loss_limit_hit?: false,
      emergency_peak_loss_exit_triggered?: false,
      profit_target_hit?: false,
      percentage_pnl_exit_hit?: false,
      premium_momentum_failure_hit?: false,
      check_structure_invalidation: nil,
      check_smc_navigator_exit: nil,
      time_based_exit?: false
    )
  end

  context 'when underlying is healthy and position is at HWM' do
    it 'does not exit — trailing not triggered' do
      result = described_class.check_exit_conditions(tracker)
      expect(result).to be_nil
    end
  end

  context 'when BOS breaks against position' do
    before do
      allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(bos_break_state)
    end

    it 'exits immediately with UNDERLYING_STRUCTURE_BREAK even though HWM not dropped' do
      result = described_class.check_exit_conditions(tracker)
      expect(result).not_to be_nil
      expect(result[:exit]).to be true
      expect(result[:reason]).to include('UNDERLYING_STRUCTURE_BREAK')
      expect(result[:path]).to eq('underlying_context_exit')
    end
  end

  context 'when trend is weak and position drops 2% from HWM' do
    before do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(snapshot_2pct_drop)
      allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(weak_trend_state)
    end

    it 'exits via TRAILING_STOP because tightened multiplier (0.5x) lowers threshold below 2%' do
      # Normal allowed_dd at 1.38 peak (>1.00 tier): 0.03
      # Tightened: 0.03 * 0.5 = 0.015 effective_allowed_dd
      # Actual drop: (39215-38430)/39215 * 1.38 ≈ 0.0276 > 0.015 → fires
      result = described_class.check_exit_conditions(tracker)
      expect(result).not_to be_nil
      expect(result[:exit]).to be true
      expect(result[:reason]).to include('TRAILING_STOP').or include('ADAPTIVE_TRAILING')
    end
  end

  context 'when underlying is healthy and position drops 5% from HWM' do
    before do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(snapshot_5pct_drop)
    end

    it 'exits via normal trailing' do
      # allowed_dd at 1.35 peak (>1.00 tier): 0.03
      # Actual drop: (39215-37260)/39215 * 1.35 ≈ 0.0673 > 0.03 → fires
      result = described_class.check_exit_conditions(tracker)
      expect(result).not_to be_nil
      expect(result[:exit]).to be true
    end
  end

  context 'when evaluate_underlying_context is not called when trailing not armed' do
    before do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: 0.05, ltp: 290.0, pnl: 1_335.0, hwm_pnl: 0.0 }
      )
    end

    it 'does not call UnderlyingMonitor' do
      described_class.check_exit_conditions(tracker)
      expect(Live::UnderlyingMonitor).not_to have_received(:evaluate)
    end
  end
end
```

- [ ] **Step 2: Run to verify failures**

```bash
bundle exec rspec spec/services/live/unified_exit_checker_spec.rb \
  -e "underlying-context-aware trailing" --format documentation 2>&1
```

Expected: failures — `evaluate_underlying_context` not defined on `UnifiedExitChecker` yet.

- [ ] **Step 3: Include the module and update `UnifiedExitChecker`**

**Edit 1** — add `include` at top of `class << self` block (after line 11):

```ruby
    class << self
      include Live::UnderlyingLtpResolver
      include Live::StructureInvalidationEvaluator
      include Live::UnderlyingContextEvaluator   # ← add this line
```

**Edit 2** — replace the trailing stop section (lines 97–105) in `check_exit_conditions`:

Old:
```ruby
        # 5. Trailing Stop (if enabled)
        if trailing_stop_hit?(tracker, snapshot)
          return {
            exit: true,
            reason: 'TRAILING_STOP',
            path: 'trailing_stop',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end
```

New:
```ruby
        # 5. Trailing Stop — underlying-context-aware
        # evaluate_underlying_context gates on trailing_armed? internally
        underlying_ctx = evaluate_underlying_context(tracker, snapshot)
        if underlying_ctx[:action] == :exit
          return {
            exit: true,
            reason: underlying_ctx[:reason],
            path: 'underlying_context_exit',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end

        if trailing_stop_hit?(tracker, snapshot, tightening_multiplier: underlying_ctx[:multiplier])
          return {
            exit: true,
            reason: 'TRAILING_STOP',
            path: 'trailing_stop',
            pnl_pct: (pnl_pct * 100.0).round(2)
          }
        end
```

**Edit 3** — update `trailing_stop_hit?` signature (line 223) to accept and pass the kwarg:

Old:
```ruby
      def trailing_stop_hit?(tracker, snapshot)
```

New:
```ruby
      def trailing_stop_hit?(tracker, snapshot, tightening_multiplier: 1.0)
```

And update the call to `adaptive_trailing_exit?` inside `trailing_stop_hit?` (line 247–249):

Old:
```ruby
          return true if adaptive_tiers.is_a?(Array) &&
                         adaptive_tiers.any? &&
                         adaptive_trailing_exit?(tracker, snapshot, peak_profit_pct, adaptive_tiers)
```

New:
```ruby
          return true if adaptive_tiers.is_a?(Array) &&
                         adaptive_tiers.any? &&
                         adaptive_trailing_exit?(tracker, snapshot, peak_profit_pct, adaptive_tiers,
                                                 tightening_multiplier: tightening_multiplier)
```

- [ ] **Step 4: Run the integration tests**

```bash
bundle exec rspec spec/services/live/unified_exit_checker_spec.rb \
  -e "underlying-context-aware trailing" --format documentation 2>&1
```

Expected: all examples pass.

- [ ] **Step 5: Run the full spec suite for `UnifiedExitChecker`**

```bash
bundle exec rspec spec/services/live/unified_exit_checker_spec.rb --format documentation 2>&1 | tail -20
```

Expected: all examples pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/services/live/unified_exit_checker.rb \
        spec/services/live/unified_exit_checker_spec.rb
git commit -m "feat: wire UnderlyingContextEvaluator into UnifiedExitChecker trailing path"
```

---

## Task 6: Run all related specs and final check

- [ ] **Step 1: Run the full evaluator + checker specs together**

```bash
bundle exec rspec spec/services/live/underlying_context_evaluator_spec.rb \
               spec/services/live/unified_exit_checker_spec.rb \
               --format documentation 2>&1 | tail -30
```

Expected: all examples pass.

- [ ] **Step 2: Run RuboCop on the new file**

```bash
bundle exec rubocop app/services/live/underlying_context_evaluator.rb --autocorrect 2>&1
```

Fix any offences, then re-run without `--autocorrect` to confirm clean.

- [ ] **Step 3: Final commit if any rubocop fixes were made**

```bash
git add app/services/live/underlying_context_evaluator.rb
git commit -m "style: rubocop fixes in UnderlyingContextEvaluator"
```

*(Skip if nothing changed.)*
