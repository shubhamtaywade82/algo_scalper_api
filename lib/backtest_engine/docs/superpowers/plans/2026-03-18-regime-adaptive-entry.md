# Regime-Adaptive Entry Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ExpiryTrendV1's fixed volume spike filter and session/day_type routing with a regime-score + IV-expansion driven adaptive entry bar.

**Architecture:** `RegimeScorer` (existing) produces a 0–100 regime score. A new `IvExpansionSignal` computes an IV delta modifier (-15..+15). `ExpiryTrendV1` combines them into an `effective_score` which determines both whether to enter and how demanding the volume threshold is. Session windows and day_type are removed from routing; regime strength is the sole gate.

**Tech Stack:** Ruby 3.3, RSpec 3.13, existing BacktestEngine gem structure.

**Spec:** `docs/superpowers/specs/2026-03-18-regime-adaptive-entry-design.md`

**Run all tests:** `bundle exec rspec`

---

## File Map

| Action | File | What changes |
|---|---|---|
| Modify | `lib/backtest_engine/market/iv_series.rb` | Add `readings_before(timestamp, n)` |
| Modify | `lib/backtest_engine/market/candle_series.rb` | Add `volume_ratio(index, period:)` |
| Create | `lib/backtest_engine/market/iv_expansion_signal.rb` | New class |
| Modify | `lib/backtest_engine/market/context_builder.rb` | Add `iv_expansion`, `volume_ratio`; remove `volume_spike` |
| Modify | `lib/backtest_engine/strategies/router.rb` | Regime-only gate; remove session/day_type |
| Modify | `lib/backtest_engine/strategies/expiry_trend_v1.rb` | Adaptive entry logic; remove time window |
| Modify | `lib/backtest_engine/backtest_session.rb` | Wire IvExpansionSignal; update DEFAULT_INDICATOR_PARAMS; update router call |
| Modify | `lib/backtest_engine/batch_runner.rb` | Remove day_type from per-day session.run call |
| Modify | `scripts/jan_2025_expiry_trend_v1.rb` | Remove volume_spike_factor; replace param_grid with manual sweeps |
| Modify | `spec/market/candle_series_spec.rb` | Add volume_ratio cases |
| Create | `spec/market/iv_expansion_signal_spec.rb` | New spec file |
| Modify | `spec/strategies/router_spec.rb` | Replace session-based tests with regime-only tests |
| Modify | `spec/strategies/expiry_trend_v1_spec.rb` | Rewrite for new call chain |
| Modify | `spec/backtest_session_spec.rb` | Remove day_type: from run call |
| Modify | `spec/batch_runner_spec.rb` | Remove day_type from per-day hash; rename/update day_type test |

---

## Task 1: `IvSeries#readings_before`

**Files:**
- Modify: `lib/backtest_engine/market/iv_series.rb`
- Test: `spec/market/iv_series_spec.rb` (create if not exists)

- [ ] **Step 1: Check for existing iv_series spec**

```bash
ls spec/market/
```

If `iv_series_spec.rb` does not exist, create it with just the require header:

```ruby
# spec/market/iv_series_spec.rb
require "spec_helper"

RSpec.describe BacktestEngine::Market::IvSeries do
end
```

- [ ] **Step 2: Write failing tests for `readings_before`**

Add inside the `describe` block:

```ruby
let(:t0) { Time.parse("2025-01-02 09:15:00") }
let(:candles) do
  10.times.map do |i|
    { timestamp: t0 + i * 60, iv: 20.0 + i }
  end
end
let(:series) { described_class.new(candles) }

describe "#readings_before" do
  it "returns last n IV floats strictly before the given timestamp" do
    result = series.readings_before(t0 + 5 * 60, 3)
    expect(result).to eq([22.0, 23.0, 24.0])
  end

  it "returns empty array when no readings exist before timestamp" do
    result = series.readings_before(t0, 3)
    expect(result).to eq([])
  end

  it "returns fewer than n when not enough readings exist" do
    result = series.readings_before(t0 + 2 * 60, 5)
    expect(result.size).to be < 5
  end

  it "works with integer timestamps" do
    result = series.readings_before((t0 + 5 * 60).to_i, 3)
    expect(result).to eq([22.0, 23.0, 24.0])
  end
end
```

- [ ] **Step 3: Run to confirm failure**

```bash
bundle exec rspec spec/market/iv_series_spec.rb --format documentation
```

Expected: `NoMethodError: undefined method 'readings_before'`

- [ ] **Step 4: Implement `readings_before` in `IvSeries`**

Add after `iv_percentile` and before `private`:

```ruby
def readings_before(timestamp, n)
  target = timestamp.to_i
  qualifying = @points.select { |c| c[:timestamp].to_i < target }
  qualifying.last(n).map { |c| c[:iv].to_f }
end
```

- [ ] **Step 5: Run tests to confirm pass**

```bash
bundle exec rspec spec/market/iv_series_spec.rb --format documentation
```

Expected: all green

- [ ] **Step 6: Run full suite to check for regressions**

```bash
bundle exec rspec
```

Expected: all green

- [ ] **Step 7: Commit**

```bash
git add lib/backtest_engine/market/iv_series.rb spec/market/iv_series_spec.rb
git commit -m "feat: add IvSeries#readings_before for rolling IV window"
```

---

## Task 2: `CandleSeries#volume_ratio`

**Files:**
- Modify: `lib/backtest_engine/market/candle_series.rb`
- Test: `spec/market/candle_series_spec.rb`

- [ ] **Step 1: Write failing tests**

Open `spec/market/candle_series_spec.rb` and add a new `describe "#volume_ratio"` block. Add this after the existing `describe "#volume_spike?"` block (or at the end of the outer describe):

```ruby
describe "#volume_ratio" do
  def candle(ts, vol)
    BacktestEngine::Market::Candle.new(
      timestamp: ts, open: 100, high: 101, low: 99, close: 100, volume: vol
    )
  end

  let(:t0) { Time.parse("2025-01-02 09:15:00") }
  let(:candles) do
    15.times.map { |i| candle(t0 + i * 60, 100) } + [candle(t0 + 15 * 60, 200)]
  end
  let(:series) { described_class.new(candles) }

  it "returns current volume divided by rolling average" do
    # candle at index 15 has volume 200; prior 10 all have volume 100 → ratio = 2.0
    expect(series.volume_ratio(15, period: 10)).to be_within(0.01).of(2.0)
  end

  it "returns 1.0 when index is less than period" do
    expect(series.volume_ratio(5, period: 10)).to eq(1.0)
  end

  it "returns 1.0 when all volume in window is zero" do
    zero_candles = 15.times.map { |i| candle(t0 + i * 60, 0) } + [candle(t0 + 15 * 60, 0)]
    zero_series = described_class.new(zero_candles)
    expect(zero_series.volume_ratio(15, period: 10)).to eq(1.0)
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/market/candle_series_spec.rb -e "volume_ratio" --format documentation
```

Expected: `NoMethodError: undefined method 'volume_ratio'`

- [ ] **Step 3: Implement `volume_ratio` in `CandleSeries`**

Add after the `volume_spike?` method (before `# Helpers`):

```ruby
def volume_ratio(index, period:)
  return 1.0 if index < period

  window = candles[(index - period)...index]
  return 1.0 if volume_unavailable?(window)

  average = window.sum(&:volume) / period.to_f
  return 1.0 if average.zero?

  candles[index].volume.to_f / average
end
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
bundle exec rspec spec/market/candle_series_spec.rb --format documentation
```

Expected: all green

- [ ] **Step 5: Run full suite**

```bash
bundle exec rspec
```

Expected: all green

- [ ] **Step 6: Commit**

```bash
git add lib/backtest_engine/market/candle_series.rb spec/market/candle_series_spec.rb
git commit -m "feat: add CandleSeries#volume_ratio for adaptive spike threshold"
```

---

## Task 3: `IvExpansionSignal`

**Files:**
- Create: `lib/backtest_engine/market/iv_expansion_signal.rb`
- Create: `spec/market/iv_expansion_signal_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/market/iv_expansion_signal_spec.rb
require "spec_helper"
require "time"

RSpec.describe BacktestEngine::Market::IvExpansionSignal do
  let(:t0) { Time.parse("2025-01-02 09:15:00") }

  def make_series(iv_values)
    candles = iv_values.each_with_index.map do |iv, i|
      { timestamp: t0 + i * 60, iv: iv.to_f }
    end
    BacktestEngine::Market::IvSeries.new(candles)
  end

  describe "#modifier_at" do
    context "when fewer than period readings exist before timestamp" do
      it "returns 0.0" do
        series = make_series([20.0, 21.0, 22.0])
        signal = described_class.new(series, period: 10)
        expect(signal.modifier_at(t0 + 2 * 60)).to eq(0.0)
      end
    end

    context "when no readings exist before timestamp" do
      it "returns 0.0" do
        series = make_series([20.0])
        signal = described_class.new(series, period: 3)
        expect(signal.modifier_at(t0)).to eq(0.0)
      end
    end

    context "when current IV is higher than rolling average" do
      it "returns a positive modifier" do
        # 10 readings at 20.0, then current at 22.0 → delta = +10%
        iv_values = Array.new(10, 20.0) + [22.0]
        series = make_series(iv_values)
        signal = described_class.new(series, period: 10)
        result = signal.modifier_at(t0 + 10 * 60)
        expect(result).to be > 0
      end
    end

    context "when current IV is lower than rolling average" do
      it "returns a negative modifier" do
        iv_values = Array.new(10, 20.0) + [18.0]
        series = make_series(iv_values)
        signal = described_class.new(series, period: 10)
        result = signal.modifier_at(t0 + 10 * 60)
        expect(result).to be < 0
      end
    end

    context "when IV expansion is extreme positive" do
      it "clamps at +15.0" do
        iv_values = Array.new(10, 10.0) + [100.0]
        series = make_series(iv_values)
        signal = described_class.new(series, period: 10)
        expect(signal.modifier_at(t0 + 10 * 60)).to eq(15.0)
      end
    end

    context "when IV expansion is extreme negative" do
      it "clamps at -15.0" do
        iv_values = Array.new(10, 100.0) + [1.0]
        series = make_series(iv_values)
        signal = described_class.new(series, period: 10)
        expect(signal.modifier_at(t0 + 10 * 60)).to eq(-15.0)
      end
    end

    context "with integer timestamps" do
      it "handles integer timestamps correctly" do
        iv_values = Array.new(10, 20.0) + [22.0]
        series = make_series(iv_values)
        signal = described_class.new(series, period: 10)
        result = signal.modifier_at((t0 + 10 * 60).to_i)
        expect(result).to be > 0
      end
    end

    context "when rolling average is zero" do
      it "returns 0.0" do
        candles = 10.times.map { |i| { timestamp: t0 + i * 60, iv: 0.0 } } +
                  [{ timestamp: t0 + 10 * 60, iv: 20.0 }]
        series = BacktestEngine::Market::IvSeries.new(candles)
        signal = described_class.new(series, period: 10)
        expect(signal.modifier_at(t0 + 10 * 60)).to eq(0.0)
      end
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/market/iv_expansion_signal_spec.rb --format documentation
```

Expected: `NameError: uninitialized constant BacktestEngine::Market::IvExpansionSignal`

- [ ] **Step 3: Create `IvExpansionSignal`**

```ruby
# lib/backtest_engine/market/iv_expansion_signal.rb
# frozen_string_literal: true

module BacktestEngine
  module Market
    class IvExpansionSignal
      DEFAULT_PERIOD = 10

      def initialize(iv_series, period: DEFAULT_PERIOD)
        @iv_series = iv_series
        @period = period
      end

      def modifier_at(timestamp)
        return 0.0 if @iv_series.nil?

        current = @iv_series.iv_for(timestamp)
        return 0.0 if current.nil?

        readings = @iv_series.readings_before(timestamp, @period)
        return 0.0 if readings.size < @period

        rolling_avg = readings.sum / @period.to_f
        return 0.0 if rolling_avg.zero?

        delta_pct = ((current - rolling_avg) / rolling_avg) * 100.0
        delta_pct.clamp(-15.0, 15.0)
      end
    end
  end
end
```

- [ ] **Step 4: Register the new file in `lib/backtest_engine.rb`**

Open `lib/backtest_engine.rb` and add a require for the new file alongside the other market requires:

```ruby
require_relative "backtest_engine/market/iv_expansion_signal"
```

- [ ] **Step 5: Run tests to confirm pass**

```bash
bundle exec rspec spec/market/iv_expansion_signal_spec.rb --format documentation
```

Expected: all green

- [ ] **Step 6: Run full suite**

```bash
bundle exec rspec
```

Expected: all green

- [ ] **Step 7: Commit**

```bash
git add lib/backtest_engine/market/iv_expansion_signal.rb \
        lib/backtest_engine.rb \
        spec/market/iv_expansion_signal_spec.rb
git commit -m "feat: add IvExpansionSignal for IV delta regime modifier"
```

---

## Task 4: Update `ContextBuilder` and `DEFAULT_INDICATOR_PARAMS`

**Files:**
- Modify: `lib/backtest_engine/market/context_builder.rb`
- Modify: `lib/backtest_engine/backtest_session.rb` (DEFAULT_INDICATOR_PARAMS only)

No separate spec needed — ContextBuilder is a plain data builder tested through integration. The change is purely additive (add two fields, remove one).

- [ ] **Step 1: Update `ContextBuilder`**

Replace the `build` method body in `lib/backtest_engine/market/context_builder.rb`:

```ruby
def self.build(index_candle:, indicators:, ltp:)
  {
    time:          index_candle.timestamp,
    price:         index_candle.close,
    structure:     indicators[:structure],
    pullback:      indicators[:pullback],
    volume_ratio:  indicators[:volume_ratio],
    iv:            indicators[:iv],
    iv_percentile: indicators[:iv_percentile],
    iv_expansion:  indicators[:iv_expansion],
    htf_bias:      indicators[:htf_bias],
    regime_score:  indicators[:regime_score],
    regime_stable: indicators[:regime_stable],
    ltp:           ltp
  }
end
```

(`volume_spike` is removed; `iv_expansion` and `volume_ratio` are added.)

- [ ] **Step 2: Update `DEFAULT_INDICATOR_PARAMS` in `BacktestSession`**

Find this constant near the top of `lib/backtest_engine/backtest_session.rb`:

```ruby
DEFAULT_INDICATOR_PARAMS = {
  pullback_ema_period: 20,
  volume_spike_factor: 1.2,
  volume_spike_period: 10
}.freeze
```

Replace with:

```ruby
DEFAULT_INDICATOR_PARAMS = {
  pullback_ema_period: 20,
  volume_spike_period: 10,
  iv_expansion_period: 10
}.freeze
```

- [ ] **Step 3: Run full suite**

```bash
bundle exec rspec
```

Expected: all green (volume_spike removal may cause failures in expiry_trend_v1_spec — that's expected and will be fixed in Task 6)

- [ ] **Step 4: Commit**

```bash
git add lib/backtest_engine/market/context_builder.rb \
        lib/backtest_engine/backtest_session.rb
git commit -m "refactor: update ContextBuilder and indicator params for adaptive entry"
```

---

## Task 5: Simplify `Router`

**Files:**
- Modify: `lib/backtest_engine/strategies/router.rb`
- Modify: `spec/strategies/router_spec.rb`

- [ ] **Step 1: Rewrite `router_spec.rb`**

Replace the entire content of `spec/strategies/router_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe BacktestEngine::Strategies::Router do
  describe "#tradable?" do
    it "returns true for trend_bull regime" do
      expect(described_class.new.tradable?(regime: :trend_bull)).to be true
    end

    it "returns true for trend_bear regime" do
      expect(described_class.new.tradable?(regime: :trend_bear)).to be true
    end

    it "returns false for chop regime" do
      expect(described_class.new.tradable?(regime: :chop)).to be false
    end

    it "returns false for nil regime" do
      expect(described_class.new.tradable?(regime: nil)).to be false
    end

    it "ignores extra keywords (backward compat splat)" do
      expect(described_class.new.tradable?(regime: :trend_bull, session: :s2, day_type: :normal)).to be true
    end
  end

  describe "#strategy_for" do
    it "returns ExpiryTrendV1 when regime is tradable" do
      expect(described_class.new.strategy_for(regime: :trend_bull)).to eq(BacktestEngine::Strategies::ExpiryTrendV1)
    end

    it "returns nil when regime is not tradable" do
      expect(described_class.new.strategy_for(regime: :chop)).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/strategies/router_spec.rb --format documentation
```

Expected: failures because current Router still has session/day_type logic.

- [ ] **Step 3: Rewrite `Router`**

Replace entire content of `lib/backtest_engine/strategies/router.rb`:

```ruby
# frozen_string_literal: true

module BacktestEngine
  module Strategies
    class Router
      TRADABLE_REGIMES = %i[trend_bull trend_bear].freeze

      def tradable?(regime:, **)
        return false if regime.nil?

        TRADABLE_REGIMES.include?(regime.to_sym)
      end

      def strategy_for(regime:, **)
        return nil unless tradable?(regime: regime)

        ExpiryTrendV1
      end
    end
  end
end
```

- [ ] **Step 4: Run router spec**

```bash
bundle exec rspec spec/strategies/router_spec.rb --format documentation
```

Expected: all green

- [ ] **Step 5: Run full suite**

```bash
bundle exec rspec
```

Expected: all green (backtest_session_spec may now have a mismatched router call — that will be fixed in Task 7)

- [ ] **Step 6: Commit**

```bash
git add lib/backtest_engine/strategies/router.rb spec/strategies/router_spec.rb
git commit -m "refactor: simplify Router to regime-only gate"
```

---

## Task 6: Rewrite `ExpiryTrendV1`

**Files:**
- Modify: `lib/backtest_engine/strategies/expiry_trend_v1.rb`
- Modify: `spec/strategies/expiry_trend_v1_spec.rb`

- [ ] **Step 1: Rewrite `expiry_trend_v1_spec.rb`**

Replace the entire content of `spec/strategies/expiry_trend_v1_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe BacktestEngine::Strategies::ExpiryTrendV1 do
  def context_for(overrides = {})
    {
      structure:    :bullish,
      pullback:     true,
      volume_ratio: 1.5,
      regime_score: 75.0,
      iv_expansion: 5.0,
      htf_bias:     :bullish,
      iv:           nil
    }.merge(overrides)
  end

  def strategy(overrides = {})
    described_class.new(context: context_for(overrides))
  end

  describe "#call" do
    context "regime gate" do
      it "skips when regime_score is nil (graceful nil-safety)" do
        result = strategy(regime_score: nil, iv_expansion: nil).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/Weak regime/)
      end

      it "skips when effective_score is below REGIME_FLOOR" do
        # score=40 + iv=0 + htf=0 = 40 < 55
        result = strategy(regime_score: 40.0, iv_expansion: 0.0, htf_bias: nil).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/Weak regime/)
      end

      it "trades when effective_score meets REGIME_FLOOR exactly" do
        # score=55 + iv=0 + htf=0 = 55 >= 55
        result = strategy(regime_score: 55.0, iv_expansion: 0.0, htf_bias: nil).call
        expect(result[:action]).to eq(:buy)
      end

      it "applies htf_bias misalignment as -5 penalty" do
        # score=58 + iv=0 + htf_misaligned=-5 = 53 < 55 → skip
        result = strategy(regime_score: 58.0, iv_expansion: 0.0, htf_bias: :bearish, structure: :bullish).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/Weak regime/)
      end

      it "does not penalise when htf_bias is nil" do
        result = strategy(regime_score: 60.0, iv_expansion: 0.0, htf_bias: nil).call
        expect(result[:action]).to eq(:buy)
      end
    end

    context "structure gate" do
      it "skips when structure is :range" do
        result = strategy(structure: :range).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/No structure/)
      end
    end

    context "pullback gate" do
      it "skips when pullback is false" do
        result = strategy(pullback: false).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/No pullback/)
      end
    end

    context "volume gate (adaptive threshold)" do
      it "skips when volume_ratio is below threshold for the score band" do
        # score=60 → factor=1.4; ratio=1.3 < 1.4 → skip
        result = strategy(regime_score: 60.0, iv_expansion: 0.0, htf_bias: nil, volume_ratio: 1.3).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/No setup/)
      end

      it "trades when volume_ratio meets threshold for the score band" do
        # score=60 → factor=1.4; ratio=1.4 >= 1.4 → trade
        result = strategy(regime_score: 60.0, iv_expansion: 0.0, htf_bias: nil, volume_ratio: 1.4).call
        expect(result[:action]).to eq(:buy)
      end

      it "uses a lower threshold at high scores" do
        # score=80 → factor=1.05; ratio=1.1 >= 1.05 → trade
        result = strategy(regime_score: 80.0, iv_expansion: 0.0, htf_bias: nil, volume_ratio: 1.1).call
        expect(result[:action]).to eq(:buy)
      end
    end

    context "direction" do
      it "generates buy call for bullish structure" do
        result = strategy(structure: :bullish).call
        expect(result[:action]).to eq(:buy)
        expect(result[:option_type]).to eq(:call)
      end

      it "generates buy put for bearish structure" do
        result = strategy(structure: :bearish, htf_bias: :bearish).call
        expect(result[:action]).to eq(:buy)
        expect(result[:option_type]).to eq(:put)
      end
    end

    context "no time window" do
      it "does not skip based on time of day (ENTRY_WINDOW removed)" do
        # strategy.call uses context_for defaults — no time field — confirms no time check exists
        result = strategy.call
        expect(result[:action]).to eq(:buy)
      end
    end
  end
end
```

- [ ] **Step 2: Run to confirm failures**

```bash
bundle exec rspec spec/strategies/expiry_trend_v1_spec.rb --format documentation
```

Expected: multiple failures

- [ ] **Step 3: Rewrite `ExpiryTrendV1`**

Replace the entire content of `lib/backtest_engine/strategies/expiry_trend_v1.rb`:

```ruby
module BacktestEngine
  module Strategies
    class ExpiryTrendV1
      MAX_HOLD_MINUTES = 25
      SL_PCT           = 30
      TARGET_PCT       = 60
      TRAIL_TRIGGER    = 40
      REGIME_FLOOR     = 55

      # Step function: iterate from highest threshold, return factor for first
      # row where effective_score >= threshold (>=, not >).
      SPIKE_CURVE = [
        [80, 1.05],
        [70, 1.2],
        [60, 1.4],
        [55, 1.8]
      ].freeze

      def initialize(context:)
        @context = context
      end

      def call
        return no_trade!("Weak regime")  unless regime_strong_enough?
        return no_trade!("No structure") unless tradable_structure?
        return no_trade!("No pullback")  unless pullback?

        if bullish_setup?
          build_trade(:call)
        elsif bearish_setup?
          build_trade(:put)
        else
          no_trade!("No setup")
        end
      end

      private

      attr_reader :context

      def effective_score
        base    = context[:regime_score].to_f
        iv_mod  = context[:iv_expansion].to_f
        htf_pen = htf_misaligned? ? -5.0 : 0.0
        (base + iv_mod + htf_pen).clamp(0.0, 100.0)
      end

      def htf_misaligned?
        htf = context[:htf_bias]
        return false if htf.nil?

        htf != context[:structure]
      end

      def regime_strong_enough?
        effective_score >= REGIME_FLOOR
      end

      def adaptive_spike_factor
        score = effective_score
        SPIKE_CURVE.each { |threshold, factor| return factor if score >= threshold }
        Float::INFINITY
      end

      def tradable_structure?
        %i[bullish bearish].include?(context[:structure])
      end

      def pullback?
        context[:pullback]
      end

      def bullish_setup?
        context[:structure] == :bullish &&
          context[:volume_ratio].to_f >= adaptive_spike_factor
      end

      def bearish_setup?
        context[:structure] == :bearish &&
          context[:volume_ratio].to_f >= adaptive_spike_factor
      end

      def strike_mode
        iv = context[:iv]

        if context[:structure] == :bullish && iv && iv < 25
          :atm_plus_1
        elsif context[:structure] == :bearish && iv && iv < 25
          :atm_minus_1
        else
          :atm
        end
      end

      def build_trade(option_type)
        {
          action:           :buy,
          option_type:      option_type,
          strike:           strike_mode,
          sl_pct:           SL_PCT,
          target_pct:       TARGET_PCT,
          trail:            true,
          trail_trigger:    TRAIL_TRIGGER,
          max_hold_minutes: MAX_HOLD_MINUTES
        }
      end

      def no_trade!(reason)
        { action: :skip, reason: reason }
      end
    end
  end
end
```

- [ ] **Step 4: Run strategy spec**

```bash
bundle exec rspec spec/strategies/expiry_trend_v1_spec.rb --format documentation
```

Expected: all green

- [ ] **Step 5: Run full suite**

```bash
bundle exec rspec
```

Expected: all green

- [ ] **Step 6: Commit**

```bash
git add lib/backtest_engine/strategies/expiry_trend_v1.rb \
        spec/strategies/expiry_trend_v1_spec.rb
git commit -m "feat: ExpiryTrendV1 adaptive entry bar driven by effective_score"
```

---

## Task 7: Wire `IvExpansionSignal` into `BacktestSession`

**Files:**
- Modify: `lib/backtest_engine/backtest_session.rb`
- Modify: `spec/backtest_session_spec.rb`

- [ ] **Step 1: Update `spec/backtest_session_spec.rb`**

The existing test passes `day_type: :expiry` — that keyword is still accepted (default `:normal`), so this test does not need to change.

However, the router call inside the session now passes only `regime:`. Verify the test still passes as-is after the session changes. No edit needed until Step 4.

- [ ] **Step 2: Update `run` method in `BacktestSession` — instantiate `IvExpansionSignal`**

In `lib/backtest_engine/backtest_session.rb`, in the `run` method, find the line:

```ruby
iv_series = build_iv_series
```

Add the next line immediately after:

```ruby
iv_expansion_signal = iv_series ? Market::IvExpansionSignal.new(iv_series, period: indicator_params[:iv_expansion_period]) : nil
```

- [ ] **Step 3: Pass `iv_expansion_signal` into `build_indicators`**

Find the `build_indicators(...)` call in `run`. Add `iv_expansion_signal: iv_expansion_signal` as a keyword argument:

```ruby
indicators = build_indicators(
  indicator_series: indicator_series,
  iv_series: iv_series,
  iv_expansion_signal: iv_expansion_signal,
  htf_bias_mapper: htf_bias_mapper,
  structure_engine_v2: structure_engine_v2,
  regime_scorer: regime_scorer_instance,
  regime_state: regime_state_instance,
  indicator_params: indicator_params,
  candle_index: index,
  timestamp: index_candle.timestamp
)
```

- [ ] **Step 4: Update `build_indicators` method signature and body**

Find the private `build_indicators` method. Add `iv_expansion_signal: nil` to its keyword args and replace the `volume_spike` line with `volume_ratio` and `iv_expansion`:

New signature:
```ruby
def build_indicators(indicator_series:, iv_series:, iv_expansion_signal: nil, htf_bias_mapper:, structure_engine_v2: nil, regime_scorer: nil, regime_state: nil, indicator_params:, candle_index:, timestamp:)
```

Replace the `base` hash — change:
```ruby
volume_spike: indicator_series.volume_spike?(
  candle_index,
  factor: indicator_params[:volume_spike_factor],
  period: indicator_params[:volume_spike_period]
),
```

With:
```ruby
volume_ratio: indicator_series.volume_ratio(
  candle_index,
  period: indicator_params[:volume_spike_period]
),
iv_expansion: iv_expansion_signal&.modifier_at(timestamp),
```

- [ ] **Step 5: Update router call site**

Find this block in `run`:

```ruby
unless router.tradable?(session: session, day_type: day_type, regime: regime)
```

Replace with:

```ruby
unless router.tradable?(regime: regime)
```

(The `session` local variable computation above it can be left in place — it is still used for `record_decision`.)

- [ ] **Step 6: Run full suite**

```bash
bundle exec rspec
```

Expected: all green

- [ ] **Step 7: Commit**

```bash
git add lib/backtest_engine/backtest_session.rb spec/backtest_session_spec.rb
git commit -m "feat: wire IvExpansionSignal into BacktestSession; update router call"
```

---

## Task 8: Update `BatchRunner` and `batch_runner_spec`

**Files:**
- Modify: `lib/backtest_engine/batch_runner.rb`
- Modify: `spec/batch_runner_spec.rb`

`BatchRunner` currently passes `day_type: day[:day_type] || :normal` to `session.run`. Since `day_type` is no longer used for routing (only for analytics tagging, and defaults to `:normal`), this line is removed. The `batch_runner_spec` has a test that checks this flow — it becomes misleading and is replaced.

- [ ] **Step 1: Update `batch_runner_spec.rb`**

In `spec/batch_runner_spec.rb`, replace the `make_day` helper to remove `day_type` from the per-day hash:

```ruby
def make_day(t0, option_closes)
  index_candles = option_closes.each_with_index.map do |_c, i|
    candle(t0 + i * 60, 100 + i, 102 + i, 99 + i, 101 + i)
  end
  option_data = {
    ["ATM", :call] => index_candles.each_with_index.map do |c, i|
      { timestamp: c.timestamp, close: option_closes[i].to_f, iv: 20 }
    end
  }
  {
    index_candles: index_candles,
    option_data: option_data
  }
end
```

Replace the second test ("passes day_type per day to BacktestSession") with:

```ruby
it "runs two days with different option data independently" do
  t1 = Time.parse("2025-01-02 12:00:00")
  day1 = make_day(t1, [80, 90, 100, 100])
  day2 = make_day(t1 + 86_400, [80, 90, 100, 100])

  result = described_class.run(
    days: [day1, day2],
    strategy_class: BacktestEngine::Strategies::ExpiryTrendV1,
    starting_capital: 100_000,
    lot_size: 50
  )

  expect(result.results.size).to eq(2)
end
```

- [ ] **Step 2: Run batch_runner_spec to confirm current state**

```bash
bundle exec rspec spec/batch_runner_spec.rb --format documentation
```

(May pass or fail — note the state before changing BatchRunner.)

- [ ] **Step 3: Update `BatchRunner#run` to remove `day_type:` from session call**

In `lib/backtest_engine/batch_runner.rb`, in the `run` method, find:

```ruby
result = session.run(
  @strategy_class,
  day_type: day[:day_type] || :normal,
  **@session_opts
)
```

Replace with:

```ruby
result = session.run(
  @strategy_class,
  **@session_opts
)
```

(`day_type` defaults to `:normal` in `BacktestSession#run`.)

- [ ] **Step 4: Run batch_runner_spec**

```bash
bundle exec rspec spec/batch_runner_spec.rb --format documentation
```

Expected: all green

- [ ] **Step 5: Run full suite**

```bash
bundle exec rspec
```

Expected: all green

- [ ] **Step 6: Commit**

```bash
git add lib/backtest_engine/batch_runner.rb spec/batch_runner_spec.rb
git commit -m "refactor: remove day_type from BatchRunner per-day session call"
```

---

## Task 9: Update Script

**Files:**
- Modify: `scripts/jan_2025_expiry_trend_v1.rb`

No spec for scripts. Validate by running the script after changes.

- [ ] **Step 1: Update `indicator_params` in the script**

Find all occurrences of `volume_spike_factor:` in the script and remove them. Find `volume_spike_period: 10` — retain it (still used for `volume_ratio`). Add `iv_expansion_period: 10` alongside it where `indicator_params` is specified.

In the single-run with tuned params (around line 134):

```ruby
indicator_params: {
  pullback_ema_period: 20,
  volume_spike_period: 10,
  iv_expansion_period: 10
}
```

- [ ] **Step 2: Replace the `param_grid` optimizer block with manual sweeps**

The `Optimizer#apply_params_to_days` only merges `day_type` into the per-day hash and cannot sweep `indicator_params` through to the session. Remove the optimizer block entirely and replace with explicit `run_session` calls that vary `iv_expansion_period`:

```ruby
print_section("Manual sweep (iv_expansion_period, regime_scorer=true)")

[5, 10, 20].each do |period|
  result = run_session(
    index_candles: index_candles,
    option_data: option_data,
    starting_capital: starting_capital,
    lot_size: lot_size,
    structure_engine: :v2,
    regime_scorer: true,
    strategy_router: true,
    indicator_params: {
      pullback_ema_period: 20,
      volume_spike_period: 10,
      iv_expansion_period: period
    }
  )
  puts "iv_expansion_period=#{period}: #{BacktestEngine::Analytics::TradeAnalytics.from_result(result).summary}"
end
```

- [ ] **Step 3: Remove `day_type:` args from `run_session` calls where not needed**

The `day_type:` keyword still works (retained with default `:normal`) so this is cosmetic cleanup only. Remove `day_type: :normal` and `day_type: :expiry` from all `run_session` calls (they will default to `:normal`).

- [ ] **Step 4: Add `regime_scorer: true` to all `run_session` calls**

Since `regime_scorer` still defaults to `false`, and `ExpiryTrendV1` now requires a regime score to trade, all run calls need:

```ruby
regime_scorer: true
```

- [ ] **Step 5: Run the script to confirm it executes without error**

```bash
bundle exec ruby scripts/jan_2025_expiry_trend_v1.rb
```

Expected: script runs to completion with trade output. Win rate and PF will differ from baseline — that is the expected outcome.

- [ ] **Step 6: Commit**

```bash
git add scripts/jan_2025_expiry_trend_v1.rb
git commit -m "chore: update script for adaptive entry bar (remove volume_spike_factor, add iv_expansion_period)"
```

---

## Task 10: Final Verification

- [ ] **Step 1: Run full test suite one final time**

```bash
bundle exec rspec --format documentation
```

Expected: all green, no pending examples

- [ ] **Step 2: Check for any remaining references to removed fields**

```bash
grep -r "volume_spike_factor\|volume_spike:" lib/ spec/ scripts/
```

Expected: no matches (or only comments)

- [ ] **Step 3: Commit if any cleanup was needed, then tag**

```bash
git log --oneline -10
```

Confirm all tasks have been committed in order.
