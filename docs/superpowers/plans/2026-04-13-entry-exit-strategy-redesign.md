# Entry + Exit Strategy Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add RSI/MACD/EMA/SMC confluence to entry signals and replace premium-noise-triggered exits with spot-anchored HWM trailing that holds winners as long as the underlying index trend is intact.

**Architecture:** Build the shared `SpotTrendEvaluator` module first (Tasks 1–2), then apply the exit fixes in order of impact (Tasks 3–5), then wire new entry indicators into `Signal::Engine` (Tasks 6–9), and finish with config cleanup (Task 10). Each task is independently testable in paper mode. Exit changes are alpha-layer only; no locked files touched.

**Tech Stack:** Ruby 3.3.4, Rails 8.0.2, RSpec, `TechnicalAnalysis` gem, existing `Indicators::` classes (RSI, MACD, ADX, Supertrend), `Smc::Detectors::Structure`, `CandleExtension` concern on `Instrument`.

---

## File Map

| Status | File | Responsibility |
|---|---|---|
| Create | `app/services/live/spot_trend_evaluator.rb` | Shared module: is the underlying spot trend still alive? |
| Create | `app/services/indicators/ema_direction_indicator.rb` | EMA 9/21 cross direction |
| Modify | `app/services/risk/rules/time_stop_rule.rb` | Bypass any profitable trade; add spot-trend bypass |
| Modify | `app/services/risk/rules/premium_momentum_failure_rule.rb` | Gate PMF on spot confirmation + -5% loss floor |
| Modify | `app/services/risk/rules/trailing_stop_rule.rb` | Spot-anchored 3-layer trailing logic |
| Modify | `app/services/signal/engine.rb` | RSI gate, MACD/SMC confidence, real IV, EMA+zone |
| Modify | `config/algo.yml` | New config keys for all above |
| Create | `spec/services/live/spot_trend_evaluator_spec.rb` | Unit tests |
| Create | `spec/services/indicators/ema_direction_indicator_spec.rb` | Unit tests |
| Modify | `spec/services/risk/rules/time_stop_rule_spec.rb` (create if missing) | Updated tests |
| Modify | `spec/services/risk/rules/premium_momentum_failure_rule_spec.rb` | Updated tests |
| Modify | `spec/services/risk/rules/trailing_stop_rule_spec.rb` | New spot-anchored tests |

---

## Task 1: SpotTrendEvaluator Module

**Purpose:** Single place for "is the underlying spot trend still alive?" — used by TrailingStopRule and PremiumMomentumFailureRule. Avoids duplicating indicator calls.

**Key facts:**
- `instrument.supertrend_signal(interval: '1')` → `:long_entry` | `:short_entry` | `nil`
- `instrument.adx(14, interval: '1')` → `Float` | `nil`
- `Smc::Detectors::Structure.new(series)` takes a `CandleSeries` — NOT `candles:` keyword
- `structure.choch?` → `false` or `{ type:, price:, index:, semantic: :choch }`
- Instrument resolved via `tracker.instrument || tracker.watchable&.instrument`

**Files:**
- Create: `app/services/live/spot_trend_evaluator.rb`
- Create: `spec/services/live/spot_trend_evaluator_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/live/spot_trend_evaluator_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::SpotTrendEvaluator do
  # Include the module under test into a plain object
  let(:evaluator_class) do
    Class.new do
      include Live::SpotTrendEvaluator
    end
  end
  subject(:evaluator) { evaluator_class.new }

  let(:instrument) { instance_double('Instrument') }
  let(:series)     { instance_double('CandleSeries', candles: []) }

  def make_tracker(side: 'long_ce', index_key: 'NIFTY')
    instance_double('PositionTracker',
      side: side,
      meta: { 'index_key' => index_key },
      instrument: instrument,
      watchable: nil)
  end

  before do
    allow(instrument).to receive(:candle_series).with(interval: '1').and_return(series)
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: { exits: { trailing: { spot_anchored: { min_adx_to_hold: 15 } } } }
    })
  end

  describe '#evaluate_spot_trend_for' do
    context 'when instrument is nil' do
      let(:tracker) { instance_double('PositionTracker', side: 'long_ce',
                        meta: { 'index_key' => 'NIFTY' }, instrument: nil, watchable: nil) }

      it 'returns trend_alive: true (fail-safe — do not exit on missing data)' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be true
        expect(result[:severity]).to eq(:none)
      end
    end

    context 'long_ce with intact trend (supertrend :long_entry, ADX 22, no CHOCH)' do
      let(:tracker) { make_tracker(side: 'long_ce') }
      let(:structure) { instance_double('Smc::Detectors::Structure') }

      before do
        allow(instrument).to receive(:supertrend_signal).with(interval: '1').and_return(:long_entry)
        allow(instrument).to receive(:adx).with(14, interval: '1').and_return(22.0)
        allow(Smc::Detectors::Structure).to receive(:new).with(series).and_return(structure)
        allow(structure).to receive(:choch?).and_return(false)
      end

      it 'returns trend_alive: true' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be true
        expect(result[:supertrend_ok]).to be true
        expect(result[:adx_ok]).to be true
        expect(result[:no_choch]).to be true
      end
    end

    context 'long_ce with supertrend flipped to :short_entry' do
      let(:tracker) { make_tracker(side: 'long_ce') }
      let(:structure) { instance_double('Smc::Detectors::Structure') }

      before do
        allow(instrument).to receive(:supertrend_signal).with(interval: '1').and_return(:short_entry)
        allow(instrument).to receive(:adx).with(14, interval: '1').and_return(22.0)
        allow(Smc::Detectors::Structure).to receive(:new).with(series).and_return(structure)
        allow(structure).to receive(:choch?).and_return(false)
      end

      it 'returns trend_alive: false, severity: :moderate' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be false
        expect(result[:severity]).to eq(:moderate)
        expect(result[:supertrend_ok]).to be false
      end
    end

    context 'long_ce with both supertrend flipped AND ADX collapsed' do
      let(:tracker) { make_tracker(side: 'long_ce') }
      let(:structure) { instance_double('Smc::Detectors::Structure') }

      before do
        allow(instrument).to receive(:supertrend_signal).with(interval: '1').and_return(:short_entry)
        allow(instrument).to receive(:adx).with(14, interval: '1').and_return(10.0)
        allow(Smc::Detectors::Structure).to receive(:new).with(series).and_return(structure)
        allow(structure).to receive(:choch?).and_return(false)
      end

      it 'returns trend_alive: false, severity: :severe' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be false
        expect(result[:severity]).to eq(:severe)
      end
    end

    context 'long_ce with CHOCH detected (trend direction still matches, ADX ok)' do
      let(:tracker) { make_tracker(side: 'long_ce') }
      let(:structure) { instance_double('Smc::Detectors::Structure') }

      before do
        allow(instrument).to receive(:supertrend_signal).with(interval: '1').and_return(:long_entry)
        allow(instrument).to receive(:adx).with(14, interval: '1').and_return(18.0)
        allow(Smc::Detectors::Structure).to receive(:new).with(series).and_return(structure)
        allow(structure).to receive(:choch?).and_return({ type: :bearish, price: 100.0, semantic: :choch })
      end

      it 'returns trend_alive: false, severity: :moderate' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be false
        expect(result[:severity]).to eq(:moderate)
      end
    end

    context 'long_pe with intact bearish trend (supertrend :short_entry)' do
      let(:tracker) { make_tracker(side: 'long_pe', index_key: 'SENSEX') }
      let(:structure) { instance_double('Smc::Detectors::Structure') }

      before do
        allow(instrument).to receive(:supertrend_signal).with(interval: '1').and_return(:short_entry)
        allow(instrument).to receive(:adx).with(14, interval: '1').and_return(25.0)
        allow(Smc::Detectors::Structure).to receive(:new).with(series).and_return(structure)
        allow(structure).to receive(:choch?).and_return(false)
      end

      it 'returns trend_alive: true' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be true
      end
    end
  end
end
```

- [ ] **Step 2: Run spec to confirm failure**

```bash
bundle exec rspec spec/services/live/spot_trend_evaluator_spec.rb --format documentation
```

Expected: All examples fail with `uninitialized constant Live::SpotTrendEvaluator`

- [ ] **Step 3: Create the module**

```ruby
# app/services/live/spot_trend_evaluator.rb
# frozen_string_literal: true

module Live
  # Shared module: answers "is the underlying spot trend still alive?"
  #
  # Used by TrailingStopRule and PremiumMomentumFailureRule to avoid
  # exiting winners based on option premium noise when the underlying
  # index trend is fully intact.
  #
  # API: evaluate_spot_trend_for(tracker) → Hash
  #   trend_alive: Boolean  — false means the trend has broken
  #   severity: :none | :mild | :moderate | :severe
  #   supertrend_ok: Boolean
  #   adx_ok: Boolean
  #   no_choch: Boolean
  #   adx_value: Float
  module SpotTrendEvaluator
    # Returns { trend_alive:, severity:, supertrend_ok:, adx_ok:, no_choch:, adx_value: }
    # Fail-safe: returns trend_alive: true when data is unavailable (never exit on missing data).
    def evaluate_spot_trend_for(tracker)
      instrument = tracker.instrument || tracker.watchable&.instrument
      return fail_safe_result unless instrument

      side      = tracker.side.to_s
      min_adx   = min_adx_to_hold

      # instrument.supertrend_signal(interval:) → :long_entry | :short_entry | nil
      # instrument.adx(period, interval:) → Float | nil
      st_signal = instrument.supertrend_signal(interval: '1') rescue nil
      adx_value = instrument.adx(14, interval: '1').to_f rescue 0.0
      series    = instrument.candle_series(interval: '1') rescue nil
      choch_detected = detect_choch(series)

      # long_ce expects :long_entry, long_pe expects :short_entry
      expected_st = side == 'long_ce' ? :long_entry : :short_entry

      supertrend_ok = st_signal == expected_st
      adx_ok        = adx_value >= min_adx
      no_choch      = !choch_detected
      trend_alive   = supertrend_ok && adx_ok && no_choch

      severity = compute_severity(supertrend_ok, adx_ok, no_choch)

      { trend_alive: trend_alive, severity: severity,
        supertrend_ok: supertrend_ok, adx_ok: adx_ok,
        no_choch: no_choch, adx_value: adx_value }
    rescue StandardError => e
      Rails.logger.warn("[SpotTrendEvaluator] Error — defaulting to trend_alive: true: #{e.message}")
      fail_safe_result
    end

    private

    def fail_safe_result
      { trend_alive: true, severity: :none,
        supertrend_ok: true, adx_ok: true, no_choch: true, adx_value: 0.0 }
    end

    def min_adx_to_hold
      AlgoConfig.fetch.dig(:risk, :exits, :trailing, :spot_anchored, :min_adx_to_hold).to_f
    rescue
      15.0
    end

    def detect_choch(series)
      return false unless series

      structure = Smc::Detectors::Structure.new(series)
      structure.choch? != false
    rescue StandardError
      false
    end

    def compute_severity(supertrend_ok, adx_ok, no_choch)
      if !supertrend_ok && !adx_ok
        :severe
      elsif !supertrend_ok || !no_choch
        :moderate
      elsif !adx_ok
        :mild
      else
        :none
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to confirm pass**

```bash
bundle exec rspec spec/services/live/spot_trend_evaluator_spec.rb --format documentation
```

Expected: All 6 examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/live/spot_trend_evaluator.rb spec/services/live/spot_trend_evaluator_spec.rb
git commit -m "feat: add SpotTrendEvaluator module for spot-anchored exit decisions"
```

---

## Task 2: EmaDirectionIndicator

**Purpose:** New indicator returning the 9/21 EMA cross direction. Used by Signal::Engine as a tie-breaking direction confirm.

**Files:**
- Create: `app/services/indicators/ema_direction_indicator.rb`
- Create: `spec/services/indicators/ema_direction_indicator_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/indicators/ema_direction_indicator_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::EmaDirectionIndicator do
  def make_series(closes)
    candles = closes.map.with_index do |c, i|
      instance_double('Candle', open: c, high: c + 1, low: c - 1, close: c, volume: 1000, timestamp: i.minutes.ago)
    end
    instance_double('CandleSeries', candles: candles)
  end

  describe '#calculate' do
    context 'with fewer candles than slow_period (21)' do
      let(:series) { make_series([100.0] * 10) }

      it 'returns direction: :neutral, aligned: false' do
        result = described_class.new(series: series).calculate
        expect(result[:direction]).to eq(:neutral)
        expect(result[:aligned]).to be false
      end
    end

    context 'with sustained uptrend (fast EMA above slow EMA)' do
      # 30 candles consistently rising — fast EMA will be above slow EMA
      let(:closes) { (1..30).map { |i| 100.0 + (i * 0.5) } }
      let(:series) { make_series(closes) }

      it 'returns direction: :bullish' do
        result = described_class.new(series: series).calculate
        expect(result[:direction]).to eq(:bullish)
        expect(result[:fast]).to be > result[:slow]
        expect(result[:aligned]).to be true
      end
    end

    context 'with sustained downtrend (fast EMA below slow EMA)' do
      # 30 candles consistently declining
      let(:closes) { (1..30).map { |i| 200.0 - (i * 0.5) } }
      let(:series) { make_series(closes) }

      it 'returns direction: :bearish' do
        result = described_class.new(series: series).calculate
        expect(result[:direction]).to eq(:bearish)
        expect(result[:fast]).to be < result[:slow]
      end
    end

    context 'with custom fast/slow periods' do
      let(:closes) { (1..30).map { |i| 100.0 + (i * 0.5) } }
      let(:series) { make_series(closes) }

      it 'uses configured periods' do
        result = described_class.new(series: series, config: { fast_period: 5, slow_period: 10 }).calculate
        expect(result[:direction]).to be_in(%i[bullish bearish neutral])
      end
    end
  end
end
```

- [ ] **Step 2: Run spec to confirm failure**

```bash
bundle exec rspec spec/services/indicators/ema_direction_indicator_spec.rb --format documentation
```

Expected: All fail with `uninitialized constant Indicators::EmaDirectionIndicator`

- [ ] **Step 3: Create the indicator**

```ruby
# app/services/indicators/ema_direction_indicator.rb
# frozen_string_literal: true

module Indicators
  # EMA 9/21 cross direction indicator.
  #
  # Returns { direction: :bullish | :bearish | :neutral, fast: Float, slow: Float,
  #           aligned: Boolean, spread_pct: Float }
  #
  # Used in Signal::Engine as a tie-breaking direction confirm:
  #   - If Supertrend says bullish but EMA says bearish → require ADX >= 25
  #   - If both agree → normal ADX threshold
  class EmaDirectionIndicator
    DEFAULT_FAST = 9
    DEFAULT_SLOW = 21

    def initialize(series:, config: {})
      @series      = series
      @fast_period = config.fetch(:fast_period, DEFAULT_FAST).to_i
      @slow_period = config.fetch(:slow_period, DEFAULT_SLOW).to_i
    end

    def calculate
      closes = @series.candles.map(&:close).map(&:to_f)
      return neutral_result if closes.size < @slow_period

      fast_val = ema(closes, @fast_period)
      slow_val = ema(closes, @slow_period)
      return neutral_result if fast_val.nil? || slow_val.nil?

      direction = if fast_val > slow_val then :bullish
                  elsif fast_val < slow_val then :bearish
                  else :neutral
                  end

      spread_pct = slow_val.positive? ? ((fast_val - slow_val).abs / slow_val * 100).round(4) : 0.0

      { direction: direction, fast: fast_val.round(4), slow: slow_val.round(4),
        aligned: direction != :neutral, spread_pct: spread_pct }
    end

    private

    # Wilder/standard EMA: k = 2 / (period + 1)
    def ema(closes, period)
      return nil if closes.size < period

      k    = 2.0 / (period + 1)
      seed = closes.first(period).sum / period.to_f

      closes.drop(period).reduce(seed) { |prev, c| c * k + prev * (1 - k) }
    end

    def neutral_result
      { direction: :neutral, fast: nil, slow: nil, aligned: false, spread_pct: 0.0 }
    end
  end
end
```

- [ ] **Step 4: Run spec to confirm pass**

```bash
bundle exec rspec spec/services/indicators/ema_direction_indicator_spec.rb --format documentation
```

Expected: All 4 examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/indicators/ema_direction_indicator.rb spec/services/indicators/ema_direction_indicator_spec.rb
git commit -m "feat: add EmaDirectionIndicator (9/21 cross) for signal tie-breaking"
```

---

## Task 3: TimeStop — Bypass Any Profitable Trade

**Current problem:** `return skip_result if pnl_pct >= 0.05` — the comment says "all profitable" but the code only bypasses at 5%+ profit. Positions at +1% to +4% are still being time-stopped.

**Change:** Single line edit — `>= 0.05` → `>= 0.0`. Add a second bypass for when the spot trend is still intact.

**Files:**
- Modify: `app/services/risk/rules/time_stop_rule.rb`
- Create/Modify: `spec/services/risk/rules/time_stop_rule_spec.rb`

- [ ] **Step 1: Write failing tests for the new bypass conditions**

Create or add to `spec/services/risk/rules/time_stop_rule_spec.rb`:

```ruby
# frozen_string_literal: true
require 'rails_helper'

RSpec.describe Risk::Rules::TimeStopRule do
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 42,
      created_at: 20.minutes.ago,
      meta: { 'index_key' => 'NIFTY', 'entry_path' => '1m_scalp' },
      instrument: nil,
      watchable: nil
    )
  end

  let(:position) do
    instance_double('Positions::ActiveCache::PositionData', pnl_pct: pnl_pct_value)
  end

  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      tracker: tracker,
      position: position,
      active?: true,
      pnl_pct: pnl_pct_value,
      tracker_snapshot: { pnl_pct: pnl_pct_value, ltp: 100.0 }
    )
  end

  let(:rule) { described_class.new(config: {}) }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        time_stop: {
          scalp: { max_minutes: 15, max_candles: 15 },
          trend: { 'NIFTY' => 30, 'BANKNIFTY' => 25, 'SENSEX' => 25 }
        },
        exits: { trailing: { spot_anchored: { min_adx_to_hold: 15 } } }
      }
    })
  end

  describe 'profitable position bypass' do
    context 'when pnl_pct is 0.0 (breakeven)' do
      let(:pnl_pct_value) { 0.0 }

      it 'does NOT time-stop a breakeven position (>= 0.0 is immune)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end

    context 'when pnl_pct is 0.02 (+2% profit, was NOT bypassed before)' do
      let(:pnl_pct_value) { 0.02 }

      it 'bypasses time stop for any profitable position' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end

    context 'when pnl_pct is -0.20 (-20%, 20 minutes elapsed, scalp type)' do
      let(:pnl_pct_value) { -0.20 }

      it 'fires TIME_STOP (losing scalp past 15 min)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('TIME_STOP')
      end
    end
  end

  describe 'spot trend bypass' do
    let(:pnl_pct_value) { -0.03 }  # Losing position
    let(:instrument)    { instance_double('Instrument') }
    let(:series)        { instance_double('CandleSeries', candles: []) }
    let(:structure)     { instance_double('Smc::Detectors::Structure') }

    before do
      allow(tracker).to receive(:instrument).and_return(instrument)
      allow(instrument).to receive(:candle_series).and_return(series)
      allow(Smc::Detectors::Structure).to receive(:new).and_return(structure)
      allow(structure).to receive(:choch?).and_return(false)
    end

    context 'when spot trend is intact (supertrend ok, ADX ok, no CHOCH)' do
      before do
        allow(instrument).to receive(:supertrend_signal).and_return(:long_entry)
        allow(instrument).to receive(:adx).and_return(20.0)
        allow(tracker).to receive(:side).and_return('long_ce')
      end

      it 'skips time stop (spot trend still alive)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
      end
    end

    context 'when spot trend is broken (supertrend flipped, ADX collapsed)' do
      before do
        allow(instrument).to receive(:supertrend_signal).and_return(:short_entry)
        allow(instrument).to receive(:adx).and_return(10.0)
        allow(tracker).to receive(:side).and_return('long_ce')
      end

      it 'allows time stop to fire (spot confirms trade is dead)' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end
  end
end
```

- [ ] **Step 2: Run to confirm failures**

```bash
bundle exec rspec spec/services/risk/rules/time_stop_rule_spec.rb --format documentation
```

Expected: Multiple failures — bypass and spot-trend tests fail.

- [ ] **Step 3: Update TimeStopRule**

In `app/services/risk/rules/time_stop_rule.rb`, replace lines 56–61:

```ruby
# OLD:
pnl_pct = context.pnl_pct.to_f
# Bypass time stop for all profitable trades — trailing system owns winners.
# PremiumMomentumFailure (2min stall) handles dead/negative trades faster and
# more precisely, so no hard 5-min negative-PnL override is needed here.
return skip_result if pnl_pct >= 0.05
```

With:

```ruby
pnl_pct = context.pnl_pct.to_f

# Any profitable position is immune — trailing system owns winners.
return skip_result if pnl_pct >= 0.0

# Spot trend still intact? Give the trade more time regardless of PnL.
return skip_result if spot_trend_alive?(tracker)
```

Also add `include Live::SpotTrendEvaluator` after the class declaration and add the private helper:

```ruby
class TimeStopRule < BaseRule
  include Live::SpotTrendEvaluator
  # ... rest of class ...

  private

  def spot_trend_alive?(tracker)
    result = evaluate_spot_trend_for(tracker)
    result[:trend_alive]
  rescue StandardError
    false  # On error, don't block the time stop
  end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/risk/rules/time_stop_rule_spec.rb --format documentation
```

Expected: All pass.

- [ ] **Step 5: Run full rule suite to check for regressions**

```bash
bundle exec rspec spec/services/risk/rules/ --format progress
```

Expected: No new failures.

- [ ] **Step 6: Commit**

```bash
git add app/services/risk/rules/time_stop_rule.rb spec/services/risk/rules/time_stop_rule_spec.rb
git commit -m "fix: time stop now bypasses all profitable positions and spot-trending trades"
```

---

## Task 4: PremiumMomentumFailure — Loss Floor + Spot Confirmation

**Current problem:** `PremiumMomentumFailureRule#evaluate` delegates fully to `Live::UnifiedExitChecker.premium_momentum_failure_hit?()` (locked). That method fires when premium stalls 2 min AND pnl ≤ 0 — triggering at breakeven on normal consolidation.

**Strategy:** Add pre-checks in the rule class BEFORE delegating to UEC. The rule returns `no_action_result` early if:
1. Loss is less than -5% (too shallow to act on)
2. Spot trend is still alive (underlying confirms no failure)

These gates run before the UEC delegation — UEC logic unchanged.

**Files:**
- Modify: `app/services/risk/rules/premium_momentum_failure_rule.rb`
- Modify: `spec/services/risk/rules/premium_momentum_failure_rule_spec.rb`

- [ ] **Step 1: Add failing tests for the new gates**

Add these contexts to `spec/services/risk/rules/premium_momentum_failure_rule_spec.rb`:

```ruby
# Add inside the main describe block, after existing tests:

describe 'minimum loss floor gate (new: -5% minimum)' do
  let(:index_key) { 'NIFTY' }
  let(:peak_at)   { 5.minutes.ago }   # Stall >= default

  before do
    allow(Time).to receive(:current).and_return(Time.zone.parse('2026-04-13 10:00:00 +05:30'))
  end

  context 'when pnl_pct is -0.02 (only -2% loss — too shallow)' do
    before { allow(context).to receive(:pnl_pct).and_return(-0.02) }

    it 'does NOT fire PMF (loss below -5% floor)' do
      result = rule.evaluate(context)
      expect(result.exit?).to be false
    end
  end

  context 'when pnl_pct is -0.06 (-6% loss, stall >= threshold)' do
    before { allow(context).to receive(:pnl_pct).and_return(-0.06) }

    it 'fires PMF (loss meets -5% floor + stall time met)' do
      result = rule.evaluate(context)
      expect(result.exit?).to be true
    end
  end
end

describe 'spot trend confirmation gate (new)' do
  let(:index_key)  { 'NIFTY' }
  let(:peak_at)    { 5.minutes.ago }
  let(:instrument) { instance_double('Instrument') }
  let(:series)     { instance_double('CandleSeries', candles: []) }
  let(:structure)  { instance_double('Smc::Detectors::Structure') }

  before do
    allow(context).to receive(:pnl_pct).and_return(-0.08)  # Meets loss floor
    allow(Time).to receive(:current).and_return(Time.zone.parse('2026-04-13 10:00:00 +05:30'))
    allow(tracker).to receive(:instrument).and_return(instrument)
    allow(tracker).to receive(:watchable).and_return(nil)
    allow(tracker).to receive(:side).and_return('long_ce')
    allow(instrument).to receive(:candle_series).and_return(series)
    allow(Smc::Detectors::Structure).to receive(:new).and_return(structure)
    allow(structure).to receive(:choch?).and_return(false)
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        exits: {
          premium_momentum_failure: pmf_config,
          trailing: { spot_anchored: { min_adx_to_hold: 15 } }
        },
        time_regimes: {
          open_expansion:     { start: '09:15', end: '09:45' },
          trend_continuation: { start: '09:45', end: '11:30' },
          chop_decay:         { start: '11:30', end: '13:45' },
          close_gamma:        { start: '13:45', end: '15:15' }
        }
      }
    })
  end

  context 'when underlying spot trend is still intact' do
    before do
      allow(instrument).to receive(:supertrend_signal).and_return(:long_entry)
      allow(instrument).to receive(:adx).and_return(20.0)
    end

    it 'does NOT fire PMF (spot not confirming failure)' do
      result = rule.evaluate(context)
      expect(result.exit?).to be false
    end
  end

  context 'when underlying spot trend has broken' do
    before do
      allow(instrument).to receive(:supertrend_signal).and_return(:short_entry)
      allow(instrument).to receive(:adx).and_return(10.0)
    end

    it 'fires PMF (spot confirms the momentum failure)' do
      result = rule.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('PREMIUM_MOMENTUM_FAILURE')
    end
  end
end
```

- [ ] **Step 2: Run to confirm failures**

```bash
bundle exec rspec spec/services/risk/rules/premium_momentum_failure_rule_spec.rb --format documentation
```

Expected: New tests fail, existing tests pass.

- [ ] **Step 3: Update PremiumMomentumFailureRule**

Replace the full file content:

```ruby
# app/services/risk/rules/premium_momentum_failure_rule.rb
# frozen_string_literal: true

module Risk
  module Rules
    # Premium Momentum Failure Rule - CRITICAL EXIT for intraday options buying
    #
    # Exits dead option trades before theta eats them. Two new gates (in addition to
    # the existing UEC check) prevent false exits on consolidation:
    #
    # Gate 1 — Loss floor: Only fires at -5% or deeper loss.
    #   Rationale: At -1% to -4%, the trade is near breakeven; premium stalling
    #   here is normal consolidation. Don't exit a trade that hasn't lost much yet.
    #
    # Gate 2 — Spot confirmation: Only fires when the underlying spot trend has also
    #   broken (Supertrend flipped OR ADX collapsed below 15 OR CHOCH detected).
    #   Rationale: Premium can stall for 2-3 minutes while the underlying consolidates.
    #   If NIFTY/SENSEX is still trending in the right direction, the option is
    #   likely to resume its move.
    #
    # Priority: 30 (checked after structure invalidation)
    class PremiumMomentumFailureRule < BaseRule
      include Live::SpotTrendEvaluator
      include SessionDetector

      PRIORITY = 30
      DEFAULT_STALL_MINUTES = 3
      MIN_LOSS_PCT_TO_FIRE  = -0.05   # Must be at -5% or worse

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        # Gate 1: Loss must be at least -5% — don't exit near-breakeven trades
        pnl_pct = context.pnl_pct.to_f
        return no_action_result if pnl_pct > MIN_LOSS_PCT_TO_FIRE

        # Gate 2: Spot trend must confirm the failure
        spot_ctx = evaluate_spot_trend_for(context.tracker)
        return no_action_result if spot_ctx[:trend_alive]

        # Both gates passed — delegate to existing UEC check for stall time logic
        if Live::UnifiedExitChecker.premium_momentum_failure_hit?(context.tracker, context.tracker_snapshot)
          return exit_result(
            reason: 'PREMIUM_MOMENTUM_FAILURE',
            metadata: {
              path: 'premium_momentum_failure',
              spot_severity: spot_ctx[:severity],
              pnl_pct: (pnl_pct * 100.0).round(2)
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[PremiumMomentumFailureRule] Error: #{e.class} - #{e.message}")
        skip_result
      end

      def enabled?(context = nil)
        pmf_cfg = config.dig(:risk, :exits, :premium_momentum_failure) || {}
        pmf_cfg[:enabled] == true
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/risk/rules/premium_momentum_failure_rule_spec.rb --format documentation
```

Expected: All pass. Existing stall-time tests still pass (UEC logic unchanged).

- [ ] **Step 5: Run full rule suite**

```bash
bundle exec rspec spec/services/risk/rules/ --format progress
```

Expected: No new failures.

- [ ] **Step 6: Commit**

```bash
git add app/services/risk/rules/premium_momentum_failure_rule.rb spec/services/risk/rules/premium_momentum_failure_rule_spec.rb
git commit -m "fix: PMF now requires -5% loss floor and spot trend confirmation before exit"
```

---

## Task 5: Spot-Anchored Trailing Stop

**Current problem:** `TrailingStopRule` delegates directly to `UnifiedExitChecker.send(:trailing_stop_hit?, ...)` which checks a fixed % drop from HWM. Option premiums oscillate 15-30% on consolidation → exits winners at +5.8% avg.

**New behaviour:** Before delegating to UEC, check the spot trend.
- If **trend alive** → only check hard floor (exit if premium < entry × 0.50). Otherwise hold.
- If **trend broken** → allow UEC trailing logic to run as normal (with severity-based tightening).

**Files:**
- Modify: `app/services/risk/rules/trailing_stop_rule.rb`
- Modify: `spec/services/risk/rules/trailing_stop_rule_spec.rb`

- [ ] **Step 1: Add failing tests**

Add to `spec/services/risk/rules/trailing_stop_rule_spec.rb`:

```ruby
# Add after existing tests

describe 'spot-anchored trailing (new 3-layer logic)' do
  let(:rule)       { described_class.new(config: risk_config) }
  let(:instrument) { instance_double('Instrument') }
  let(:series)     { instance_double('CandleSeries', candles: []) }
  let(:structure)  { instance_double('Smc::Detectors::Structure') }

  before do
    allow(tracker).to receive(:instrument).and_return(instrument)
    allow(tracker).to receive(:watchable).and_return(nil)
    allow(tracker).to receive(:side).and_return('long_pe')
    allow(tracker).to receive(:meta).and_return({ 'index_key' => 'NIFTY' })
    allow(instrument).to receive(:candle_series).and_return(series)
    allow(Smc::Detectors::Structure).to receive(:new).and_return(structure)
    allow(structure).to receive(:choch?).and_return(false)
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        exits: {
          trailing: {
            spot_anchored: {
              enabled: true,
              min_adx_to_hold: 15,
              hard_floor_pct: 0.50
            }
          }
        }
      }
    })
    position_data.pnl_pct = 30.0   # 30% profit — trailing is armed
  end

  context 'Layer 1: spot trend alive — position at 30% profit, premium above hard floor' do
    before do
      allow(instrument).to receive(:supertrend_signal).and_return(:short_entry) # PE expects short
      allow(instrument).to receive(:adx).and_return(22.0)
      position_data.instance_variable_set(:@current_ltp, 90.0)  # above 50% floor
      allow(tracker).to receive(:entry_price).and_return(100.0)
    end

    it 'does NOT exit (holds while spot trend intact regardless of HWM drop)' do
      result = rule.evaluate(context)
      expect(result.exit?).to be false
    end
  end

  context 'Layer 2: spot trend alive — premium drops below hard floor (50% of entry)' do
    before do
      allow(instrument).to receive(:supertrend_signal).and_return(:short_entry)
      allow(instrument).to receive(:adx).and_return(22.0)
      allow(tracker).to receive(:entry_price).and_return(100.0)
      # Simulate snapshot with LTP below hard floor
      allow(context).to receive(:tracker_snapshot).and_return(
        { pnl_pct: 0.30, ltp: 45.0, hwm_pnl: 3000.0, pnl: 1000.0 }
      )
    end

    it 'exits (TRAILING_HARD_FLOOR — premium below 50% of entry despite trend alive)' do
      result = rule.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('TRAILING_HARD_FLOOR')
    end
  end

  context 'Layer 3: spot trend broken — delegates to existing UEC trailing logic' do
    before do
      allow(instrument).to receive(:supertrend_signal).and_return(:long_entry) # Wrong for long_pe
      allow(instrument).to receive(:adx).and_return(10.0)
    end

    it 'allows the underlying UEC trailing check to run' do
      # UEC check may or may not fire depending on HWM — just verify it proceeds
      expect(Live::UnifiedExitChecker).to receive(:send)
        .with(:evaluate_underlying_context, anything, anything)
        .and_call_original rescue nil
      rule.evaluate(context)
    end
  end
end
```

- [ ] **Step 2: Run to confirm failures**

```bash
bundle exec rspec spec/services/risk/rules/trailing_stop_rule_spec.rb --format documentation
```

Expected: New tests fail.

- [ ] **Step 3: Update TrailingStopRule**

Replace the full content of `app/services/risk/rules/trailing_stop_rule.rb`:

```ruby
# app/services/risk/rules/trailing_stop_rule.rb
# frozen_string_literal: true

module Risk
  module Rules
    # Trailing Stop Rule — Spot-Anchored HWM
    #
    # Three-layer exit logic:
    #
    # Layer 1 (Spot Trend Alive):
    #   Hold unconditionally as long as the underlying spot trend is intact
    #   (Supertrend direction matches position, ADX >= min_adx_to_hold, no CHOCH).
    #   Only the hard_floor_pct safety net applies.
    #
    # Layer 2 (Hard Floor):
    #   Exit if option premium falls below entry_price × (1 - hard_floor_pct).
    #   Default: 50% below entry. Prevents catastrophic loss if data is stale.
    #
    # Layer 3 (Spot Broken):
    #   Spot trend has broken. Delegate to existing UnifiedExitChecker trailing
    #   logic with severity-aware tightening multiplier.
    class TrailingStopRule < BaseRule
      include Live::SpotTrendEvaluator

      PRIORITY = 50

      def evaluate(context)
        return skip_result unless context.active?

        tracker  = context.tracker
        snapshot = context.tracker_snapshot
        pnl_pct  = snapshot[:pnl_pct].to_f

        # Only engage once trailing is armed (positive PnL)
        return no_action_result unless pnl_pct.positive?

        spot_ctx = evaluate_spot_trend_for(tracker)

        if spot_ctx[:trend_alive]
          # Layer 1: Trend intact — only apply hard floor safety net
          return check_hard_floor(tracker, snapshot)
        end

        # Layer 3: Spot trend broken — evaluate with UEC trailing + severity tightening
        tightening = severity_multiplier(spot_ctx[:severity])

        underlying_ctx = Live::UnifiedExitChecker.send(
          :evaluate_underlying_context, tracker, snapshot
        )

        if underlying_ctx[:action] == :exit
          return exit_result(
            reason: underlying_ctx[:reason],
            metadata: {
              path: 'underlying_context_exit',
              spot_severity: spot_ctx[:severity],
              pnl_pct: (pnl_pct * 100.0).round(2)
            }
          )
        end

        combined_multiplier = [tightening * underlying_ctx[:multiplier], 0.3].max

        if Live::UnifiedExitChecker.send(:trailing_stop_hit?, tracker, snapshot,
                                         tightening_multiplier: combined_multiplier)
          return exit_result(
            reason: 'TRAILING_SPOT_BREAK',
            metadata: {
              path: 'trailing_spot_break',
              spot_severity: spot_ctx[:severity],
              pnl_pct: (pnl_pct * 100.0).round(2)
            }
          )
        end

        no_action_result
      end

      private

      def check_hard_floor(tracker, snapshot)
        entry_price = tracker.entry_price.to_f
        return no_action_result if entry_price.zero?

        floor_pct   = hard_floor_pct
        hard_floor  = entry_price * (1.0 - floor_pct)
        current_ltp = snapshot[:ltp].to_f

        return no_action_result if current_ltp >= hard_floor

        exit_result(
          reason: 'TRAILING_HARD_FLOOR',
          metadata: {
            path: 'trailing_hard_floor',
            entry_price: entry_price,
            current_ltp: current_ltp,
            hard_floor: hard_floor.round(2),
            floor_pct: (floor_pct * 100).round(1)
          }
        )
      end

      def hard_floor_pct
        AlgoConfig.fetch.dig(:risk, :exits, :trailing, :spot_anchored, :hard_floor_pct).to_f
      rescue
        0.50
      end

      def severity_multiplier(severity)
        case severity
        when :severe   then 0.50  # Very tight when both Supertrend + ADX broken
        when :moderate then 0.65  # Tighter when one condition broken
        when :mild     then 0.80
        else                1.00
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/risk/rules/trailing_stop_rule_spec.rb --format documentation
```

Expected: All pass.

- [ ] **Step 5: Run full rule suite**

```bash
bundle exec rspec spec/services/risk/rules/ --format progress
```

Expected: No new failures.

- [ ] **Step 6: Commit**

```bash
git add app/services/risk/rules/trailing_stop_rule.rb spec/services/risk/rules/trailing_stop_rule_spec.rb
git commit -m "feat: trailing stop now holds winners while spot trend intact, exits on spot structure break"
```

---

## Task 6: Signal Engine — RSI Anti-Chase Gate

**Purpose:** Add RSI as the 6th validation check in `comprehensive_validation()`. It blocks CE entries when RSI is overbought (>78) and PE entries when RSI is oversold (<22). It does NOT block entries in the normal trending RSI zone (45–75 for CE, 25–55 for PE).

**Context in `signal/engine.rb`:**
- Find `comprehensive_validation` method
- It returns early with a failure hash when a check fails
- The return pattern is: `return { valid: false, reason: '...', check: :name }`
- Find the last existing check and add the RSI check after it
- `RsiIndicator` exists at `app/services/indicators/rsi_indicator.rb` — call `RsiIndicator.new(series: series).calculate_at(-1)` to get `{ value:, direction:, confidence: }`

- [ ] **Step 1: Read the current comprehensive_validation signature**

```bash
grep -n "def comprehensive_validation\|def.*validate\|return.*valid.*false\|valid: false" \
  app/services/signal/engine.rb | head -20
```

Note the exact return format used for failures (needed to match in Step 3).

- [ ] **Step 2: Write a targeted spec for the RSI gate**

Create `spec/services/signal/engine_rsi_gate_spec.rb`:

```ruby
# spec/services/signal/engine_rsi_gate_spec.rb
# frozen_string_literal: true

require 'rails_helper'

# Focused spec for the RSI anti-chase gate added to Signal::Engine#comprehensive_validation.
# Tests the gate in isolation by stubbing AlgoConfig and the RSI indicator.
RSpec.describe 'Signal::Engine RSI anti-chase gate' do
  let(:engine) { Signal::Engine.new }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      signals: {
        validation_modes: {
          balanced: {
            require_rsi_check: true,
            rsi_overbought_block: 78,
            rsi_oversold_block: 22
          }
        }
      }
    })
  end

  # Helper: build a minimal candle series double
  def make_series(rsi_value)
    series = instance_double('CandleSeries', candles: [double(close: 100.0)] * 20)
    indicator = instance_double('Indicators::RsiIndicator', calculate_at: { value: rsi_value })
    allow(Indicators::RsiIndicator).to receive(:new).with(series: series).and_return(indicator)
    series
  end

  describe 'CE entry (bullish direction)' do
    context 'RSI at 82 (overbought — chasing a top)' do
      it 'blocks the entry' do
        result = engine.send(:validate_rsi_gate, :bullish, make_series(82), { require_rsi_check: true, rsi_overbought_block: 78 })
        expect(result[:valid]).to be false
        expect(result[:reason]).to include('RSI overbought')
      end
    end

    context 'RSI at 60 (normal bullish momentum zone)' do
      it 'passes' do
        result = engine.send(:validate_rsi_gate, :bullish, make_series(60), { require_rsi_check: true, rsi_overbought_block: 78 })
        expect(result[:valid]).to be true
      end
    end
  end

  describe 'PE entry (bearish direction)' do
    context 'RSI at 15 (oversold — chasing a bottom)' do
      it 'blocks the entry' do
        result = engine.send(:validate_rsi_gate, :bearish, make_series(15), { require_rsi_check: true, rsi_oversold_block: 22 })
        expect(result[:valid]).to be false
        expect(result[:reason]).to include('RSI oversold')
      end
    end

    context 'RSI at 38 (normal bearish momentum zone)' do
      it 'passes' do
        result = engine.send(:validate_rsi_gate, :bearish, make_series(38), { require_rsi_check: true, rsi_oversold_block: 22 })
        expect(result[:valid]).to be true
      end
    end

    context 'require_rsi_check: false' do
      it 'always passes regardless of RSI' do
        result = engine.send(:validate_rsi_gate, :bearish, make_series(10), { require_rsi_check: false })
        expect(result[:valid]).to be true
      end
    end
  end
end
```

- [ ] **Step 3: Run spec to confirm failure**

```bash
bundle exec rspec spec/services/signal/engine_rsi_gate_spec.rb --format documentation
```

Expected: Fail with `undefined method 'validate_rsi_gate'`

- [ ] **Step 4: Add `validate_rsi_gate` private method to Signal::Engine**

In `app/services/signal/engine.rb`, add this private method (near the other validate_* methods):

```ruby
# RSI anti-chase gate — call from comprehensive_validation as the 6th check.
# Blocks CE entries when RSI is overbought (no chasing tops).
# Blocks PE entries when RSI is oversold (no chasing bottoms).
# Does NOT interfere with the normal 45–75 CE zone or 25–55 PE zone.
def validate_rsi_gate(direction, series, mode_config)
  return { valid: true } unless mode_config[:require_rsi_check]

  rsi_result = Indicators::RsiIndicator.new(series: series).calculate_at(-1)
  rsi_val    = rsi_result[:value].to_f

  if direction == :bullish && rsi_val > mode_config.fetch(:rsi_overbought_block, 78).to_f
    return { valid: false, reason: "RSI overbought (#{rsi_val.round(1)}) — avoid chasing CE entry", check: :rsi_overbought }
  end

  if direction == :bearish && rsi_val < mode_config.fetch(:rsi_oversold_block, 22).to_f
    return { valid: false, reason: "RSI oversold (#{rsi_val.round(1)}) — avoid chasing PE entry", check: :rsi_oversold }
  end

  { valid: true, rsi_value: rsi_val }
rescue StandardError => e
  Rails.logger.warn("[Signal::Engine] RSI gate error — allowing through: #{e.message}")
  { valid: true }
end
```

Then in `comprehensive_validation`, after the last existing check, add:

```ruby
# Check 6: RSI anti-chase gate
if mode_config[:require_rsi_check]
  rsi_check = validate_rsi_gate(final_direction, series, mode_config)
  return rsi_check unless rsi_check[:valid]
end
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/services/signal/engine_rsi_gate_spec.rb --format documentation
```

Expected: All 5 pass.

- [ ] **Step 6: Update algo.yml with RSI gate config**

In `config/algo.yml`, under `signals.validation_modes`, add to each mode:

```yaml
signals:
  validation_modes:
    balanced:
      require_rsi_check: true
      rsi_overbought_block: 78
      rsi_oversold_block: 22
    conservative:
      require_rsi_check: true
      rsi_overbought_block: 72
      rsi_oversold_block: 28
    aggressive:
      require_rsi_check: false
```

- [ ] **Step 7: Run signal engine specs to check for regressions**

```bash
bundle exec rspec spec/services/signal/ --format progress
```

Expected: No new failures.

- [ ] **Step 8: Commit**

```bash
git add app/services/signal/engine.rb config/algo.yml spec/services/signal/engine_rsi_gate_spec.rb
git commit -m "feat: add RSI anti-chase gate to signal validation (blocks overbought CE / oversold PE)"
```

---

## Task 7: Signal Engine — MACD + SMC Confidence Score Factors

**Purpose:** Wire MACD histogram direction and SMC BiasEngine alignment into `calculate_confidence_score()`. Neither blocks an entry — they boost confidence score when aligned.

**Context in `signal/engine.rb`:**
- Find `calculate_confidence_score` — it builds a score from `base_confidence + adx_factor + confirmation_factor + validation_factor + supertrend_factor`
- `MacdIndicator` exists: `MacdIndicator.new(series: series).calculate_at(-1)` → `{ value: { macd:, signal:, histogram: }, direction:, confidence: }`
- SMC BiasEngine: `Smc::BiasEngine.new(index_cfg: index_cfg).compute` → returns something with a direction; check the actual method by running `grep -n "def compute\|def call\|def bias" app/services/smc/bias_engine.rb`

- [ ] **Step 1: Verify SMC BiasEngine interface**

```bash
grep -n "def compute\|def call\|def bias\|def direction\|def result" \
  app/services/smc/bias_engine.rb | head -10
```

Note the exact method name and return format. Use this to populate Step 4.

- [ ] **Step 2: Write failing spec**

Create `spec/services/signal/engine_confidence_score_spec.rb`:

```ruby
# spec/services/signal/engine_confidence_score_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signal::Engine confidence score enhancements' do
  let(:engine) { Signal::Engine.new }

  def make_series
    instance_double('CandleSeries', candles: [double(close: 100.0)] * 30)
  end

  describe '#macd_confidence_factor' do
    context 'bullish direction with positive MACD histogram' do
      it 'returns 0.10' do
        series = make_series
        allow(Indicators::MacdIndicator).to receive(:new)
          .and_return(double(calculate_at: { value: { histogram: 0.5 }, direction: :bullish }))
        expect(engine.send(:macd_confidence_factor, :bullish, series)).to eq(0.10)
      end
    end

    context 'bearish direction with negative MACD histogram' do
      it 'returns 0.10' do
        series = make_series
        allow(Indicators::MacdIndicator).to receive(:new)
          .and_return(double(calculate_at: { value: { histogram: -0.3 }, direction: :bearish }))
        expect(engine.send(:macd_confidence_factor, :bearish, series)).to eq(0.10)
      end
    end

    context 'direction mismatch (bearish direction but positive histogram)' do
      it 'returns 0.0' do
        series = make_series
        allow(Indicators::MacdIndicator).to receive(:new)
          .and_return(double(calculate_at: { value: { histogram: 0.5 }, direction: :bullish }))
        expect(engine.send(:macd_confidence_factor, :bearish, series)).to eq(0.0)
      end
    end

    context 'when MacdIndicator raises' do
      it 'returns 0.0 safely' do
        series = make_series
        allow(Indicators::MacdIndicator).to receive(:new).and_raise(StandardError)
        expect(engine.send(:macd_confidence_factor, :bullish, series)).to eq(0.0)
      end
    end
  end

  describe '#smc_bias_confidence_factor' do
    let(:index_cfg) { double('IndexConfig', key: 'NIFTY') }

    context 'SMC bias fully aligns with signal direction' do
      it 'returns 0.20' do
        allow(engine).to receive(:get_smc_bias_direction).with(index_cfg).and_return(:bullish)
        expect(engine.send(:smc_bias_confidence_factor, :bullish, index_cfg)).to eq(0.20)
      end
    end

    context 'SMC bias is neutral' do
      it 'returns 0.05' do
        allow(engine).to receive(:get_smc_bias_direction).with(index_cfg).and_return(:neutral)
        expect(engine.send(:smc_bias_confidence_factor, :bullish, index_cfg)).to eq(0.05)
      end
    end

    context 'SMC bias misaligned' do
      it 'returns 0.0' do
        allow(engine).to receive(:get_smc_bias_direction).with(index_cfg).and_return(:bearish)
        expect(engine.send(:smc_bias_confidence_factor, :bullish, index_cfg)).to eq(0.0)
      end
    end
  end
end
```

- [ ] **Step 3: Run to confirm failure**

```bash
bundle exec rspec spec/services/signal/engine_confidence_score_spec.rb --format documentation
```

Expected: Fail with `undefined method 'macd_confidence_factor'`

- [ ] **Step 4: Add private methods to Signal::Engine**

In `app/services/signal/engine.rb`, add these private methods:

```ruby
# Returns +0.10 when MACD histogram direction aligns with entry direction.
def macd_confidence_factor(direction, series)
  result = Indicators::MacdIndicator.new(series: series).calculate_at(-1)
  histogram = result.dig(:value, :histogram).to_f
  return 0.10 if direction == :bullish && histogram > 0
  return 0.10 if direction == :bearish && histogram < 0
  0.0
rescue StandardError => e
  Rails.logger.debug("[Signal::Engine] MACD factor error: #{e.message}")
  0.0
end

# Returns +0.20 when SMC BiasEngine direction aligns, +0.05 when neutral, 0.0 when misaligned.
# Replaces the existing binary SMC gate for SCORING purposes — hard :blocked gate is preserved.
def smc_bias_confidence_factor(direction, index_cfg)
  smc_direction = get_smc_bias_direction(index_cfg)
  return 0.20 if smc_direction == direction
  return 0.05 if smc_direction == :neutral
  0.0
rescue StandardError => e
  Rails.logger.debug("[Signal::Engine] SMC bias factor error: #{e.message}")
  0.0
end

# Resolves the SMC bias direction for the given index config.
# Uses the existing Smc::BiasEngine — check app/services/smc/bias_engine.rb for the
# exact method name (compute/call/bias) and normalise to :bullish | :bearish | :neutral.
def get_smc_bias_direction(index_cfg)
  # Adjust the method call below based on Step 1 findings
  bias_result = Smc::BiasEngine.new(index_cfg: index_cfg).compute rescue nil
  return :neutral unless bias_result

  case bias_result[:direction]&.to_sym
  when :bullish, :long  then :bullish
  when :bearish, :short then :bearish
  else :neutral
  end
end
```

Then in `calculate_confidence_score`, add the two new factors:

```ruby
# After existing factors, before capping at 1.0:
confidence += macd_confidence_factor(final_direction, series)
confidence += smc_bias_confidence_factor(final_direction, index_cfg)

[confidence, 1.0].min
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/services/signal/engine_confidence_score_spec.rb --format documentation
```

Expected: All pass.

- [ ] **Step 6: Verify Smc::BiasEngine interface and fix `get_smc_bias_direction` if needed**

```bash
bundle exec rspec spec/services/signal/ --format progress
```

If any signal spec fails due to Smc::BiasEngine, check the actual interface:

```bash
grep -n "def compute\|def call\|def bias\|:direction\|:bullish\|:bearish" \
  app/services/smc/bias_engine.rb | head -20
```

Adjust `get_smc_bias_direction` accordingly and re-run.

- [ ] **Step 7: Commit**

```bash
git add app/services/signal/engine.rb spec/services/signal/engine_confidence_score_spec.rb
git commit -m "feat: MACD histogram and SMC BiasEngine now contribute to signal confidence score"
```

---

## Task 8: Signal Engine — Real IV Filter

**Purpose:** Replace the 5-candle price-volatility proxy with actual `implied_volatility` from the option chain. Block entries when IV > 75% (pre-event spike risk) or < 10% (dead market).

**Context:**
- Current method: `validate_iv_rank` in `engine.rb` — uses `avg(|price_change|) * 1000`
- Real IV source: `analysis_context[:option_data][:implied_volatility]` — already populated by `Options::ChainAnalyzer` / `DhanAdapter`
- Find the method with: `grep -n "def validate_iv_rank\|iv_rank\|iv_proxy" app/services/signal/engine.rb | head -20`

- [ ] **Step 1: Locate current IV validation method**

```bash
grep -n "def validate_iv_rank\|def.*iv_rank\|iv_proxy\|iv_rank_min\|iv_rank_max\|avg_volatility" \
  app/services/signal/engine.rb | head -15
```

Note the method name and how `analysis_context` is threaded through (it may be a local variable or instance variable).

- [ ] **Step 2: Write failing spec**

Create `spec/services/signal/engine_iv_filter_spec.rb`:

```ruby
# spec/services/signal/engine_iv_filter_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signal::Engine real IV filter' do
  let(:engine) { Signal::Engine.new }

  describe '#validate_iv_rank_real' do
    let(:mode_config) { { iv_rank_min: 0.10, iv_rank_max: 0.75 } }

    context 'IV data is zero or nil (unavailable)' do
      it 'passes through (fail-open)' do
        result = engine.send(:validate_iv_rank_real, 0.0, mode_config)
        expect(result[:valid]).to be true
      end
    end

    context 'IV is 0.50 (within range)' do
      it 'passes' do
        result = engine.send(:validate_iv_rank_real, 0.50, mode_config)
        expect(result[:valid]).to be true
      end
    end

    context 'IV is 0.82 (above max — pre-event spike)' do
      it 'blocks the entry' do
        result = engine.send(:validate_iv_rank_real, 0.82, mode_config)
        expect(result[:valid]).to be false
        expect(result[:reason]).to include('IV too high')
      end
    end

    context 'IV is 0.05 (below min — dead market)' do
      it 'blocks the entry' do
        result = engine.send(:validate_iv_rank_real, 0.05, mode_config)
        expect(result[:valid]).to be false
        expect(result[:reason]).to include('IV too low')
      end
    end

    context 'IV exactly at max (0.75)' do
      it 'passes (boundary — not strictly above max)' do
        result = engine.send(:validate_iv_rank_real, 0.75, mode_config)
        expect(result[:valid]).to be true
      end
    end
  end
end
```

- [ ] **Step 3: Run to confirm failure**

```bash
bundle exec rspec spec/services/signal/engine_iv_filter_spec.rb --format documentation
```

Expected: Fail with `undefined method 'validate_iv_rank_real'`

- [ ] **Step 4: Add method to Signal::Engine**

```ruby
# Validates implied volatility from actual option chain data.
# iv: Float — the implied_volatility field from DhanAdapter option chain (e.g. 0.45 = 45%)
# mode_config: Hash with :iv_rank_min and :iv_rank_max keys
def validate_iv_rank_real(iv, mode_config)
  iv_f = iv.to_f
  return { valid: true } if iv_f.zero?  # No IV data — fail open

  iv_max = mode_config.fetch(:iv_rank_max, 0.75).to_f
  iv_min = mode_config.fetch(:iv_rank_min, 0.10).to_f

  if iv_f > iv_max
    return { valid: false,
             reason: "IV too high (#{(iv_f * 100).round(1)}%) — IV crush risk, avoid entry",
             check: :iv_too_high }
  end

  if iv_f < iv_min
    return { valid: false,
             reason: "IV too low (#{(iv_f * 100).round(1)}%) — insufficient premium",
             check: :iv_too_low }
  end

  { valid: true, iv: iv_f }
end
```

Then in `comprehensive_validation` (or `validate_iv_rank`), replace the proxy calculation with a call to `validate_iv_rank_real`:

```ruby
# Replace old proxy calculation:
# iv_rank_result = validate_iv_rank(index_cfg, series, mode_config)
# With:
option_iv = analysis_context.dig(:option_data, :implied_volatility).to_f rescue 0.0
iv_check  = validate_iv_rank_real(option_iv, mode_config)
return iv_check unless iv_check[:valid]
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/services/signal/engine_iv_filter_spec.rb --format documentation
bundle exec rspec spec/services/signal/ --format progress
```

Expected: All pass, no regressions.

- [ ] **Step 6: Update algo.yml**

```yaml
signals:
  validation_modes:
    balanced:
      iv_rank_max: 0.75
      iv_rank_min: 0.10
    conservative:
      iv_rank_max: 0.60
      iv_rank_min: 0.10
    aggressive:
      iv_rank_max: 0.90
      iv_rank_min: 0.05
```

- [ ] **Step 7: Commit**

```bash
git add app/services/signal/engine.rb config/algo.yml spec/services/signal/engine_iv_filter_spec.rb
git commit -m "feat: replace IV proxy with real implied_volatility from option chain data"
```

---

## Task 9: Signal Engine — EMA Direction Tie-Break + SMC Zone Filter

**Purpose:**
1. **EMA tie-break**: If Supertrend and EMA disagree, require ADX ≥ 25 (prevents weak cross-current entries).
2. **SMC zone filter**: Block CE entries when price is in SMC premium zone (ADX < 30), block PE entries in discount zone.

- [ ] **Step 1: Write failing spec**

Create `spec/services/signal/engine_ema_zone_spec.rb`:

```ruby
# spec/services/signal/engine_ema_zone_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signal::Engine EMA tie-break and SMC zone filter' do
  let(:engine) { Signal::Engine.new }

  def make_series(count: 30)
    instance_double('CandleSeries', candles: [double(close: 100.0)] * count)
  end

  describe '#ema_direction_aligned?' do
    context 'Supertrend and EMA agree (both bullish)' do
      it 'returns aligned: true, adx_override_needed: false' do
        series = make_series
        allow(Indicators::EmaDirectionIndicator).to receive(:new)
          .and_return(double(calculate: { direction: :bullish }))
        result = engine.send(:check_ema_direction_alignment, :bullish, series, 20.0)
        expect(result[:aligned]).to be true
        expect(result[:adx_override_needed]).to be false
      end
    end

    context 'Supertrend bullish but EMA bearish, ADX 22 (below override threshold)' do
      it 'returns requires_adx_override: true (caller should block if ADX < 25)' do
        series = make_series
        allow(Indicators::EmaDirectionIndicator).to receive(:new)
          .and_return(double(calculate: { direction: :bearish }))
        result = engine.send(:check_ema_direction_alignment, :bullish, series, 22.0)
        expect(result[:adx_override_needed]).to be true
      end
    end

    context 'Supertrend bullish but EMA bearish, ADX 28 (above 25 threshold)' do
      it 'returns aligned: true (strong momentum overrides EMA disagreement)' do
        series = make_series
        allow(Indicators::EmaDirectionIndicator).to receive(:new)
          .and_return(double(calculate: { direction: :bearish }))
        result = engine.send(:check_ema_direction_alignment, :bullish, series, 28.0)
        expect(result[:aligned]).to be true
      end
    end
  end

  describe '#smc_zone_allows_entry?' do
    let(:index_cfg) { double('IndexConfig') }

    context 'CE entry in discount zone (ideal)' do
      it 'returns true' do
        allow(engine).to receive(:get_smc_zone).with(index_cfg).and_return(:discount)
        expect(engine.send(:smc_zone_allows_entry?, :bullish, index_cfg, 20.0)).to be true
      end
    end

    context 'CE entry in premium zone, ADX 22 (below override threshold of 30)' do
      it 'returns false (chasing top in premium zone)' do
        allow(engine).to receive(:get_smc_zone).with(index_cfg).and_return(:premium)
        expect(engine.send(:smc_zone_allows_entry?, :bullish, index_cfg, 22.0)).to be false
      end
    end

    context 'CE entry in premium zone, ADX 32 (strong momentum override)' do
      it 'returns true (momentum overrides zone restriction)' do
        allow(engine).to receive(:get_smc_zone).with(index_cfg).and_return(:premium)
        expect(engine.send(:smc_zone_allows_entry?, :bullish, index_cfg, 32.0)).to be true
      end
    end

    context 'PE entry in premium zone (ideal for puts)' do
      it 'returns true' do
        allow(engine).to receive(:get_smc_zone).with(index_cfg).and_return(:premium)
        expect(engine.send(:smc_zone_allows_entry?, :bearish, index_cfg, 20.0)).to be true
      end
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/services/signal/engine_ema_zone_spec.rb --format documentation
```

- [ ] **Step 3: Add private methods to Signal::Engine**

```ruby
# EMA direction tie-break: if Supertrend and EMA 9/21 disagree,
# require ADX >= 25 to proceed (strong momentum overrides cross-current).
def check_ema_direction_alignment(direction, series, adx_value)
  ema_result = Indicators::EmaDirectionIndicator.new(series: series).calculate
  ema_direction = ema_result[:direction]

  if ema_direction == :neutral || ema_direction == direction
    return { aligned: true, adx_override_needed: false, ema_direction: ema_direction }
  end

  # Disagreement: allow if ADX >= 25 (strong underlying momentum)
  adx_override_threshold = 25.0
  if adx_value.to_f >= adx_override_threshold
    return { aligned: true, adx_override_needed: false, ema_direction: ema_direction,
             note: 'EMA disagreement overridden by ADX strength' }
  end

  { aligned: false, adx_override_needed: true, ema_direction: ema_direction,
    required_adx: adx_override_threshold, actual_adx: adx_value }
end

# SMC Discount/Premium zone filter:
# CE (bullish): ideal in discount; blocked in premium unless ADX >= 30.
# PE (bearish): ideal in premium; blocked in discount unless ADX >= 30.
def smc_zone_allows_entry?(direction, index_cfg, adx_value)
  zone = get_smc_zone(index_cfg)
  return true if zone == :equilibrium  # Neutral zone — always allow

  zone_override_adx = AlgoConfig.fetch.dig(:signals, :smc, :zone_filter_adx_override).to_f rescue 30.0

  if direction == :bullish && zone == :premium
    return adx_value.to_f >= zone_override_adx
  end

  if direction == :bearish && zone == :discount
    return adx_value.to_f >= zone_override_adx
  end

  true  # CE in discount or PE in premium — ideal, always allow
rescue StandardError => e
  Rails.logger.debug("[Signal::Engine] SMC zone filter error: #{e.message}")
  true  # Fail open
end

# Resolves current SMC zone from Smc::Detectors::PremiumDiscount.
# Adjust the method call if the interface differs.
def get_smc_zone(index_cfg)
  instrument = resolve_spot_instrument(index_cfg) rescue nil
  return :equilibrium unless instrument

  series = instrument.candle_series(interval: '5') rescue nil
  return :equilibrium unless series

  pd = Smc::Detectors::PremiumDiscount.new(series) rescue nil
  return :equilibrium unless pd

  pd.zone rescue :equilibrium
end
```

Then wire into `execute_execution_gates` (or wherever entry checks are run), after the existing SMC permission check:

```ruby
# EMA tie-break
ema_check = check_ema_direction_alignment(final_direction, series, adx_value)
unless ema_check[:aligned]
  return execution_gate_failure("EMA direction cross-current (EMA #{ema_check[:ema_direction]}, signal #{final_direction}) — ADX #{adx_value} < #{ema_check[:required_adx]} required")
end

# SMC zone filter
unless smc_zone_allows_entry?(final_direction, index_cfg, adx_value)
  return execution_gate_failure("SMC zone mismatch — #{final_direction} entry in #{get_smc_zone(index_cfg)} zone requires ADX >= 30")
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/services/signal/engine_ema_zone_spec.rb --format documentation
bundle exec rspec spec/services/signal/ --format progress
```

Expected: All pass.

- [ ] **Step 5: Update algo.yml**

```yaml
signals:
  smc:
    use_as_scored_confluence: true
    discount_premium_zone_filter: true
    zone_filter_adx_override: 30
  indicators:
    - type: ema_direction
      enabled: true
      config: { fast_period: 9, slow_period: 21 }
```

- [ ] **Step 6: Commit**

```bash
git add app/services/signal/engine.rb config/algo.yml spec/services/signal/engine_ema_zone_spec.rb
git commit -m "feat: add EMA 9/21 tie-break and SMC discount/premium zone filter to entry gates"
```

---

## Task 10: Config Finalization + Trailing Config + Paper Mode Smoke Test

**Purpose:** Add the `trailing.spot_anchored` config block (required by `SpotTrendEvaluator` and `TrailingStopRule`) and run a paper-mode smoke test to verify the changes work end-to-end.

- [ ] **Step 1: Add trailing.spot_anchored config to algo.yml**

```yaml
risk:
  exits:
    trailing:
      spot_anchored:
        enabled: true
        min_adx_to_hold: 15
        hard_floor_pct: 0.50
        spot_break_drawdown:
          severe: 0.15
          moderate: 0.22
          mild: 0.28
    premium_momentum_failure:
      default_stall_minutes: 6        # Raised from 2–3
      min_loss_pct: 0.05              # New: -5% floor
      require_spot_confirmation: true # New: spot must confirm
    time_stop:
      scalp:
        max_minutes: 15
        max_candles: 15
      trend:
        NIFTY: 30
        BANKNIFTY: 25
        SENSEX: 25
```

- [ ] **Step 2: Run the full test suite**

```bash
bundle exec rspec --format progress
```

Expected: Green (or no new failures beyond pre-existing ones). Fix any regressions before proceeding.

- [ ] **Step 3: Check for RuboCop violations**

```bash
bundle exec rubocop app/services/live/spot_trend_evaluator.rb \
  app/services/indicators/ema_direction_indicator.rb \
  app/services/risk/rules/time_stop_rule.rb \
  app/services/risk/rules/premium_momentum_failure_rule.rb \
  app/services/risk/rules/trailing_stop_rule.rb \
  --autocorrect-all
```

- [ ] **Step 4: Paper-mode smoke test**

Start the trading daemon in paper mode:

```bash
ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon
```

Wait for at least 5 positions to exit (or review next market session's results), then run:

```bash
bundle exec rails runner "
puts '=== Exit Rule Breakdown (last 24h) ==='
exited = PositionTracker.where(status: 'exited').where('created_at > ?', 24.hours.ago)
if exited.empty?
  puts 'No exited positions yet'
else
  by_reason = exited.group_by { |p|
    r = p.meta&.dig('exit_reason') || 'unknown'
    case r
    when /TRAILING_SPOT_BREAK/  then 'TRAILING_SPOT_BREAK (new)'
    when /TRAILING_HARD_FLOOR/  then 'TRAILING_HARD_FLOOR (new)'
    when /TRAILING_STOP/        then 'TRAILING_STOP (old)'
    when /PREMIUM_MOMENTUM/     then 'PREMIUM_MOMENTUM'
    when /TIME_STOP/            then 'TIME_STOP'
    when /STOP_LOSS/            then 'STOP_LOSS'
    when /PERCENTAGE_PNL/       then 'PERCENTAGE_PNL'
    else r[0..30]
    end
  }
  puts '%-35s %5s  %8s  %5s' % ['Exit Reason', 'Count', 'Avg PnL%', 'Win%']
  puts '-' * 60
  by_reason.sort_by { |_, v| -v.count }.each do |reason, ps|
    pnls   = ps.map { |p| p.last_pnl_pct.to_f }
    avg    = (pnls.sum / pnls.count * 100).round(1)
    winpct = (pnls.count { |p| p > 0 }.to_f / pnls.count * 100).round(0)
    puts '%-35s %5d  %7.1f%%  %4d%%' % [reason, pnls.count, avg, winpct]
  end
end
"
```

**Expected results after fix:**
- `TRAILING_SPOT_BREAK` appears (new exit path)
- `TRAILING_HARD_FLOOR` may appear for catastrophic protection
- `TIME_STOP` count is much lower (spot-trend bypass filters most)
- `PREMIUM_MOMENTUM` win rate > 30% (spot confirmation filters false fires)
- `TRAILING_SPOT_BREAK` avg PnL > +15%

- [ ] **Step 5: Final commit**

```bash
git add config/algo.yml
git commit -m "config: add spot_anchored trailing, PMF recalibration, and time_stop config"
```

---

## Self-Review

### Spec Coverage Check

| Spec Section | Task |
|---|---|
| SpotTrendEvaluator module | Task 1 |
| EmaDirectionIndicator | Task 2 |
| TimeStop bypass fix | Task 3 |
| PMF loss floor + spot confirm | Task 4 |
| Spot-anchored trailing 3-layer | Task 5 |
| RSI anti-chase gate | Task 6 |
| MACD + SMC confidence | Task 7 |
| Real IV filter | Task 8 |
| EMA tie-break + SMC zone filter | Task 9 |
| Config additions | Task 10 |

**All spec requirements covered.**

### Key Assumptions (verify during Task 7 and 9)
- `Smc::BiasEngine.new(index_cfg:).compute` — verify exact method name in Step 1 of Task 7
- `Smc::Detectors::PremiumDiscount.new(series).zone` — verify in Task 9 Step 3
- `analysis_context[:option_data][:implied_volatility]` path — verify the exact key in Task 8 Step 4
- `execution_gate_failure(msg)` — verify this method exists in `Signal::Engine`; if not, use the actual failure return pattern found in Step 1 of Task 6
