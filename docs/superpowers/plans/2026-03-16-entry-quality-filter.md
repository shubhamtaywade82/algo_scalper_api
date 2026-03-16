# Entry Quality Filter Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hybrid hard-gates + quality-scoring filter to reject weak Supertrend+ADX entries before strike selection.

**Architecture:** New `Signal::EntryQualityFilter` class with class-level `evaluate` method. Two-phase: 4 hard gates (any fail = reject) then 5-component scoring (0-100, min 40). Integrates into `Signal::Engine.run_for` after validation/regime detection, before strike selection. Log-only mode for exit testing.

**Tech Stack:** Ruby, RSpec, YAML config (`algo.yml`)

**Spec:** `docs/superpowers/specs/2026-03-16-entry-quality-filter-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `app/services/signal/entry_quality_filter.rb` | CREATE | Hard gates + quality scoring filter |
| `spec/services/signal/entry_quality_filter_spec.rb` | CREATE | Unit tests for filter |
| `config/algo.yml` | MODIFY | Add `entry_quality:` config section |
| `config/profiles/exit_testing.yml` | MODIFY | Add `entry_quality.enforce: false` override |
| `app/services/signal/engine.rb` | MODIFY | Call `EntryQualityFilter.evaluate` in shared code path (after validation, before strike selection) |

---

## Chunk 1: Core Filter + Config

### Task 1: Config — Add `entry_quality` section to `algo.yml`

**Files:**
- Modify: `config/algo.yml` (add section at end, before any trailing whitespace)
- Modify: `config/profiles/exit_testing.yml` (add override)

- [ ] **Step 1: Add `entry_quality:` section to `config/algo.yml`**

Add this YAML block at the end of `config/algo.yml` (after the last existing section):

```yaml
# ===== ENTRY QUALITY FILTER =====
entry_quality:
  enforce: true                      # false = log-only mode (no blocking)
  min_score: 40                      # minimum quality score to enter (0-100)
  gates:
    min_adx: 20                      # hard gate: minimum ADX value
    block_choppy_regime: true        # hard gate: block CHOPPY regime
    min_body_ratio: 0.40             # hard gate: minimum candle body/range ratio
    require_momentum_confirm: true   # hard gate: close must be beyond Supertrend level
  scoring:
    candle_body_weight: 25           # max points for candle body strength
    adx_strength_weight: 20          # max points for ADX bonus
    bos_weight: 20                   # max points for break of structure
    range_expansion_weight: 20       # max points for range expansion
    momentum_weight: 15              # max points for momentum strength
  index_overrides:
    SENSEX:
      min_adx: 22                    # SENSEX is noisier, needs higher ADX
```

- [ ] **Step 2: Add `entry_quality.enforce: false` to `config/profiles/exit_testing.yml`**

Add this block to the exit testing profile:

```yaml
entry_quality:
  enforce: false                     # log-only in exit testing mode
```

- [ ] **Step 3: Verify config loads**

Run: `bundle exec rails runner "puts AlgoConfig.fetch[:entry_quality].inspect"`
Expected: Hash with `enforce: true`, `min_score: 40`, `gates:` sub-hash.

- [ ] **Step 4: Commit**

```bash
git add config/algo.yml config/profiles/exit_testing.yml
git commit -m "feat: add entry_quality config section to algo.yml and exit_testing profile"
```

---

### Task 2: Hard Gates — Write Tests

**Files:**
- Create: `spec/services/signal/entry_quality_filter_spec.rb`

The test file uses helpers to build inputs. Write ALL hard gate tests first (red phase).

- [ ] **Step 1: Write the test file with hard gate specs**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::EntryQualityFilter do
  # --- Helpers ---

  def build_candle(open:, high:, low:, close:, time: Time.current)
    OpenStruct.new(open: open, high: high, low: low, close: close, time: time)
  end

  def build_series(candles)
    series = instance_double('CandleSeries')
    allow(series).to receive(:candles).and_return(candles)
    series
  end

  def build_supertrend(last_value:, atr_last: 10.0, trend: :bullish)
    {
      trend: trend,
      last_value: last_value,
      atr: [nil, nil, atr_last],
      line: [nil, nil, last_value]
    }
  end

  # Default valid inputs (bullish flip with strong candle)
  let(:strong_candle) { build_candle(open: 100.0, high: 115.0, low: 95.0, close: 112.0) }
  let(:series) { build_series([strong_candle]) }
  let(:supertrend_result) { build_supertrend(last_value: 105.0, atr_last: 10.0) }
  let(:default_params) do
    {
      series: series,
      supertrend_result: supertrend_result,
      adx_value: 25.0,
      direction: :bullish,
      regime: 'TRENDING_UP',
      index_key: 'NIFTY'
    }
  end

  before do
    # Stub AlgoConfig to return entry_quality config
    allow(AlgoConfig).to receive(:fetch).and_return({
      entry_quality: {
        enforce: true,
        min_score: 40,
        gates: {
          min_adx: 20,
          block_choppy_regime: true,
          min_body_ratio: 0.40,
          require_momentum_confirm: true
        },
        scoring: {
          candle_body_weight: 25,
          adx_strength_weight: 20,
          bos_weight: 20,
          range_expansion_weight: 20,
          momentum_weight: 15
        },
        index_overrides: {
          'SENSEX' => { min_adx: 22 }
        }
      }
    })
    # Stub BosExtractor to avoid needing real CandleSeries
    allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(nil)
  end

  describe 'hard gates' do
    context 'Gate 1: ADX minimum' do
      it 'rejects when ADX < 20' do
        result = described_class.evaluate(**default_params.merge(adx_value: 17.0))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('min_adx')
        expect(result[:gates][:adx]).to be false
      end

      it 'passes when ADX == 20' do
        result = described_class.evaluate(**default_params.merge(adx_value: 20.0))
        expect(result[:gates][:adx]).to be true
      end

      it 'passes when ADX > 20' do
        result = described_class.evaluate(**default_params.merge(adx_value: 25.0))
        expect(result[:gates][:adx]).to be true
      end

      it 'rejects nil ADX' do
        result = described_class.evaluate(**default_params.merge(adx_value: nil))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('min_adx')
      end
    end

    context 'Gate 2: Regime not CHOPPY' do
      it 'rejects CHOPPY regime' do
        result = described_class.evaluate(**default_params.merge(regime: 'CHOPPY'))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('regime')
        expect(result[:gates][:regime]).to be false
      end

      it 'passes RANGING regime' do
        result = described_class.evaluate(**default_params.merge(regime: 'RANGING'))
        expect(result[:gates][:regime]).to be true
      end

      it 'passes TRENDING_UP regime' do
        result = described_class.evaluate(**default_params.merge(regime: 'TRENDING_UP'))
        expect(result[:gates][:regime]).to be true
      end

      it 'handles symbol input gracefully' do
        result = described_class.evaluate(**default_params.merge(regime: :choppy))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('regime')
      end
    end

    context 'Gate 3: Candle body ratio' do
      it 'rejects doji candle (body_ratio 0.1)' do
        doji = build_candle(open: 100.0, high: 110.0, low: 90.0, close: 102.0)
        s = build_series([doji])
        result = described_class.evaluate(**default_params.merge(series: s))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('body_ratio')
        expect(result[:gates][:body_ratio]).to be false
      end

      it 'passes strong candle (body_ratio 0.6)' do
        candle = build_candle(open: 100.0, high: 115.0, low: 95.0, close: 112.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params.merge(series: s))
        expect(result[:gates][:body_ratio]).to be true
      end

      it 'rejects zero-range candle (high == low)' do
        flat = build_candle(open: 100.0, high: 100.0, low: 100.0, close: 100.0)
        s = build_series([flat])
        result = described_class.evaluate(**default_params.merge(series: s))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('body_ratio')
      end
    end

    context 'Gate 4: Momentum confirmation' do
      it 'rejects bullish flip when close < supertrend' do
        candle = build_candle(open: 100.0, high: 110.0, low: 95.0, close: 103.0)
        st = build_supertrend(last_value: 105.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params.merge(series: s, supertrend_result: st))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('momentum')
        expect(result[:gates][:momentum]).to be false
      end

      it 'passes bullish flip when close > supertrend' do
        result = described_class.evaluate(**default_params)
        expect(result[:gates][:momentum]).to be true
      end

      it 'rejects bearish flip when close > supertrend' do
        candle = build_candle(open: 110.0, high: 115.0, low: 95.0, close: 107.0)
        st = build_supertrend(last_value: 105.0, trend: :bearish)
        s = build_series([candle])
        result = described_class.evaluate(**default_params.merge(
          series: s, supertrend_result: st, direction: :bearish
        ))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('momentum')
      end

      it 'passes bearish flip when close < supertrend' do
        candle = build_candle(open: 110.0, high: 115.0, low: 90.0, close: 98.0)
        st = build_supertrend(last_value: 105.0, trend: :bearish)
        s = build_series([candle])
        result = described_class.evaluate(**default_params.merge(
          series: s, supertrend_result: st, direction: :bearish
        ))
        expect(result[:gates][:momentum]).to be true
      end
    end

    context 'edge cases' do
      it 'rejects nil series gracefully' do
        result = described_class.evaluate(**default_params.merge(series: nil))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('no_candle_data')
      end

      it 'rejects empty candles gracefully' do
        s = build_series([])
        result = described_class.evaluate(**default_params.merge(series: s))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('no_candle_data')
      end

      it 'rejects nil supertrend_result gracefully' do
        result = described_class.evaluate(**default_params.merge(supertrend_result: nil))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('no_supertrend_data')
      end
    end
  end

  describe 'index overrides' do
    it 'uses SENSEX min_adx override of 22' do
      result = described_class.evaluate(**default_params.merge(index_key: 'SENSEX', adx_value: 21.0))
      expect(result[:pass]).to be false
      expect(result[:reject_reason]).to eq('min_adx')
    end

    it 'passes SENSEX when ADX >= 22' do
      result = described_class.evaluate(**default_params.merge(index_key: 'SENSEX', adx_value: 22.0))
      expect(result[:gates][:adx]).to be true
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/signal/entry_quality_filter_spec.rb`
Expected: All tests FAIL (class does not exist yet).

- [ ] **Step 3: Commit**

```bash
git add spec/services/signal/entry_quality_filter_spec.rb
git commit -m "test: add hard gate tests for Signal::EntryQualityFilter (red)"
```

---

### Task 3: Hard Gates — Implement

**Files:**
- Create: `app/services/signal/entry_quality_filter.rb`

- [ ] **Step 1: Implement the filter class with hard gates (scoring returns placeholder)**

```ruby
# frozen_string_literal: true

module Signal
  class EntryQualityFilter
    DEFAULTS = {
      enforce: false,
      min_score: 40,
      gates: {
        min_adx: 20,
        block_choppy_regime: true,
        min_body_ratio: 0.40,
        require_momentum_confirm: true
      },
      scoring: {
        candle_body_weight: 25,
        adx_strength_weight: 20,
        bos_weight: 20,
        range_expansion_weight: 20,
        momentum_weight: 15
      },
      index_overrides: {}
    }.freeze

    class << self
      def evaluate(series:, supertrend_result:, adx_value:, direction:, regime:, index_key:)
        config = load_config(index_key)
        candles = series&.candles || []

        # Edge case: no data
        if candles.empty?
          return reject_result('no_candle_data')
        end
        if supertrend_result.nil?
          return reject_result('no_supertrend_data')
        end

        # Phase 1: Hard gates
        gate_result = check_gates(candles, supertrend_result, adx_value, direction, regime, config)
        unless gate_result[:pass]
          log_result(index_key, direction, gate_result, nil, false)
          return gate_result
        end

        # Phase 2: Scoring (placeholder — implemented in Task 5)
        score_result = calculate_score(candles, supertrend_result, adx_value, direction, series, config)

        pass = score_result[:score] >= config[:min_score]
        log_result(index_key, direction, gate_result, score_result, pass)

        {
          pass: pass,
          score: score_result[:score],
          gates: gate_result[:gates],
          breakdown: score_result[:breakdown],
          reject_reason: pass ? nil : "score_below_threshold (#{score_result[:score]} < #{config[:min_score]})"
        }
      end

      private

      def load_config(index_key)
        raw = AlgoConfig.fetch.dig(:entry_quality) || {}
        config = deep_symbolize(DEFAULTS.deep_merge(raw))

        # Apply index-specific overrides (check Symbol and String keys)
        overrides = config.dig(:index_overrides, index_key.to_sym) ||
                    config.dig(:index_overrides, index_key.to_s) || {}
        overrides = deep_symbolize(overrides)

        if overrides[:min_adx]
          config[:gates] = config[:gates].merge(min_adx: overrides[:min_adx])
        end

        config
      end

      def deep_symbolize(hash)
        return hash unless hash.is_a?(Hash)
        hash.each_with_object({}) do |(k, v), result|
          result[k.to_sym] = v.is_a?(Hash) ? deep_symbolize(v) : v
        end
      end

      def check_gates(candles, supertrend_result, adx_value, direction, regime, config)
        gates = {}
        gate_cfg = config[:gates]

        # Gate 1: ADX minimum
        gates[:adx] = adx_value.to_f >= gate_cfg[:min_adx].to_f
        unless gates[:adx]
          return { pass: false, score: 0, gates: gates, breakdown: {}, reject_reason: 'min_adx' }
        end

        # Gate 2: Regime not CHOPPY (configurable via block_choppy_regime)
        if gate_cfg.fetch(:block_choppy_regime, true)
          gates[:regime] = regime.to_s.upcase != 'CHOPPY'
        else
          gates[:regime] = true
        end
        unless gates[:regime]
          return { pass: false, score: 0, gates: gates, breakdown: {}, reject_reason: 'regime' }
        end

        # Gate 3: Candle body ratio
        candle = candles.last
        range = candle.high - candle.low
        body_ratio = range > 0 ? (candle.close - candle.open).abs / range : 0.0
        gates[:body_ratio] = body_ratio >= gate_cfg[:min_body_ratio].to_f
        unless gates[:body_ratio]
          return { pass: false, score: 0, gates: gates, breakdown: {}, reject_reason: 'body_ratio' }
        end

        # Gate 4: Momentum confirmation (configurable via require_momentum_confirm)
        if gate_cfg.fetch(:require_momentum_confirm, true)
          st_value = supertrend_result[:last_value].to_f
          if direction == :bullish
            gates[:momentum] = candle.close > st_value
          else
            gates[:momentum] = candle.close < st_value
          end
        else
          gates[:momentum] = true
        end
        unless gates[:momentum]
          return { pass: false, score: 0, gates: gates, breakdown: {}, reject_reason: 'momentum' }
        end

        { pass: true, gates: gates }
      end

      def calculate_score(_candles, _supertrend_result, _adx_value, _direction, _series, config)
        # Placeholder — returns minimum passing score. Implemented in Task 5.
        { score: config[:min_score], breakdown: {} }
      end

      def reject_result(reason)
        { pass: false, score: 0, gates: {}, breakdown: {}, reject_reason: reason }
      end

      def log_result(index_key, direction, gate_result, score_result, pass)
        score = score_result ? score_result[:score] : 0
        breakdown = score_result ? score_result[:breakdown] : {}
        status = pass ? 'PASS' : 'REJECT'
        reason = gate_result[:reject_reason]

        Rails.logger.info(
          "[EntryQualityFilter] #{status} #{index_key} #{direction} | " \
          "score=#{score} gates=#{gate_result[:gates]} breakdown=#{breakdown}" \
          "#{reason ? " reason=#{reason}" : ''}"
        )
      end
    end
  end
end
```

- [ ] **Step 2: Run hard gate tests**

Run: `bundle exec rspec spec/services/signal/entry_quality_filter_spec.rb`
Expected: All hard gate tests PASS. Scoring tests (not yet written) N/A.

- [ ] **Step 3: Commit**

```bash
git add app/services/signal/entry_quality_filter.rb
git commit -m "feat: implement Signal::EntryQualityFilter hard gates"
```

---

### Task 4: Quality Scoring — Write Tests

**Files:**
- Modify: `spec/services/signal/entry_quality_filter_spec.rb` (add scoring describe block)

- [ ] **Step 1: Add scoring tests to the spec file**

Append inside the top-level `RSpec.describe` block, after the `describe 'index overrides'` block:

```ruby
  describe 'quality scoring' do
    # All tests use default_params which passes all gates (ADX 25, TRENDING_UP, strong candle, close > ST)

    context 'Component 1: Candle body strength (0-25)' do
      it 'scores 10 for body_ratio 0.40-0.55' do
        # body_ratio = |104 - 100| / (110 - 90) = 4/20 = 0.20 — too low, won't pass gate
        # Use 0.45: |109 - 100| / (110 - 90) = 9/20 = 0.45
        candle = build_candle(open: 100.0, high: 110.0, low: 90.0, close: 109.0)
        st = build_supertrend(last_value: 105.0, atr_last: 20.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params.merge(series: s, supertrend_result: st))
        expect(result[:breakdown][:candle_body]).to eq(10)
      end

      it 'scores 18 for body_ratio 0.55-0.70' do
        # body_ratio = |112 - 100| / (115 - 95) = 12/20 = 0.60
        result = described_class.evaluate(**default_params)
        expect(result[:breakdown][:candle_body]).to eq(18)
      end

      it 'scores 25 for body_ratio >= 0.70' do
        # body_ratio = |115 - 100| / (118 - 97) = 15/21 = 0.714
        candle = build_candle(open: 100.0, high: 118.0, low: 97.0, close: 115.0)
        st = build_supertrend(last_value: 105.0, atr_last: 21.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params.merge(series: s, supertrend_result: st))
        expect(result[:breakdown][:candle_body]).to eq(25)
      end
    end

    context 'Component 2: ADX strength bonus (0-20)' do
      it 'scores 5 for ADX 20-25' do
        result = described_class.evaluate(**default_params.merge(adx_value: 22.0))
        expect(result[:breakdown][:adx_strength]).to eq(5)
      end

      it 'scores 12 for ADX 25-35' do
        result = described_class.evaluate(**default_params.merge(adx_value: 30.0))
        expect(result[:breakdown][:adx_strength]).to eq(12)
      end

      it 'scores 20 for ADX >= 35' do
        result = described_class.evaluate(**default_params.merge(adx_value: 40.0))
        expect(result[:breakdown][:adx_strength]).to eq(20)
      end
    end

    context 'Component 3: Break of structure (0-20)' do
      it 'scores 20 when BOS confirmed in signal direction' do
        allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(
          { direction: :bullish }
        )
        result = described_class.evaluate(**default_params)
        expect(result[:breakdown][:bos]).to eq(20)
      end

      it 'scores 10 for simple structure (higher highs) without BOS' do
        # 3 candles with rising highs for bullish simple structure
        c1 = build_candle(open: 95.0, high: 100.0, low: 90.0, close: 98.0, time: 1.minute.ago)
        c2 = build_candle(open: 98.0, high: 105.0, low: 93.0, close: 103.0, time: 30.seconds.ago)
        c3 = build_candle(open: 100.0, high: 115.0, low: 95.0, close: 112.0)
        s = build_series([c1, c2, c3])
        result = described_class.evaluate(**default_params.merge(series: s))
        expect(result[:breakdown][:bos]).to eq(10)
      end

      it 'scores 0 when no structure confirmation' do
        # Single candle, no BOS, no structure pattern
        result = described_class.evaluate(**default_params)
        expect(result[:breakdown][:bos]).to eq(0)
      end
    end

    context 'Component 4: Range expansion (0-20)' do
      it 'scores 20 when range >= 1.5x ATR' do
        # range = 115 - 95 = 20, ATR = 10 → 2.0x
        result = described_class.evaluate(**default_params)
        expect(result[:breakdown][:range_expansion]).to eq(20)
      end

      it 'scores 12 when range >= 1.2x ATR' do
        # range = 115 - 95 = 20, ATR = 15 → 1.33x
        st = build_supertrend(last_value: 105.0, atr_last: 15.0)
        result = described_class.evaluate(**default_params.merge(supertrend_result: st))
        expect(result[:breakdown][:range_expansion]).to eq(12)
      end

      it 'scores 5 when range >= 1.0x ATR' do
        # range = 115 - 95 = 20, ATR = 18 → 1.11x
        st = build_supertrend(last_value: 105.0, atr_last: 18.0)
        result = described_class.evaluate(**default_params.merge(supertrend_result: st))
        expect(result[:breakdown][:range_expansion]).to eq(5)
      end

      it 'scores 0 when range < 1.0x ATR' do
        # range = 115 - 95 = 20, ATR = 25 → 0.80x
        st = build_supertrend(last_value: 105.0, atr_last: 25.0)
        result = described_class.evaluate(**default_params.merge(supertrend_result: st))
        expect(result[:breakdown][:range_expansion]).to eq(0)
      end

      it 'scores 0 when ATR is zero' do
        st = build_supertrend(last_value: 105.0, atr_last: 0.0)
        result = described_class.evaluate(**default_params.merge(supertrend_result: st))
        expect(result[:breakdown][:range_expansion]).to eq(0)
      end

      it 'scores 0 when ATR is nil' do
        st = { trend: :bullish, last_value: 105.0, atr: [nil, nil, nil], line: [nil, nil, 105.0] }
        result = described_class.evaluate(**default_params.merge(supertrend_result: st))
        expect(result[:breakdown][:range_expansion]).to eq(0)
      end
    end

    context 'Component 5: Momentum confirmation strength (0-15)' do
      it 'scores 15 when distance >= 0.5x ATR' do
        # distance = (112 - 105) / 10 = 0.7 → >= 0.5
        result = described_class.evaluate(**default_params)
        expect(result[:breakdown][:momentum]).to eq(15)
      end

      it 'scores 10 when distance >= 0.25x ATR' do
        # distance = (108 - 105) / 10 = 0.3 → >= 0.25
        candle = build_candle(open: 100.0, high: 115.0, low: 95.0, close: 108.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params.merge(series: s))
        expect(result[:breakdown][:momentum]).to eq(10)
      end

      it 'scores 3 when distance < 0.25x ATR' do
        # distance = (106 - 105) / 10 = 0.1 → < 0.25
        candle = build_candle(open: 100.0, high: 115.0, low: 95.0, close: 106.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params.merge(series: s))
        expect(result[:breakdown][:momentum]).to eq(3)
      end

      it 'scores 3 when ATR is zero (minimum since momentum gate passed)' do
        st = build_supertrend(last_value: 105.0, atr_last: 0.0)
        # Momentum gate: close 112 > 105 → passes
        result = described_class.evaluate(**default_params.merge(supertrend_result: st))
        expect(result[:breakdown][:momentum]).to eq(3)
      end

      it 'scores bearish distance correctly' do
        # bearish: distance = (105 - 92) / 10 = 1.3 → >= 0.5
        candle = build_candle(open: 110.0, high: 115.0, low: 90.0, close: 92.0)
        st = build_supertrend(last_value: 105.0, trend: :bearish)
        s = build_series([candle])
        result = described_class.evaluate(**default_params.merge(
          series: s, supertrend_result: st, direction: :bearish
        ))
        expect(result[:breakdown][:momentum]).to eq(15)
      end
    end

    context 'threshold' do
      it 'fails when total score < min_score (40)' do
        # ADX 20 → 5pts, body 0.45 → 10pts, no BOS → 0, range < ATR → 0, momentum low → 3 = 18
        candle = build_candle(open: 100.0, high: 110.0, low: 90.0, close: 109.0)
        st = build_supertrend(last_value: 105.0, atr_last: 25.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params.merge(
          series: s, supertrend_result: st, adx_value: 20.0
        ))
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to match(/score_below_threshold/)
      end

      it 'passes when total score >= min_score (40)' do
        # Default params: ADX 25 → 12pts (25-35 range), body 0.60 → 18pts, no BOS → 0,
        # range 2.0x → 20pts, momentum 0.7x → 15pts = 65
        result = described_class.evaluate(**default_params)
        expect(result[:pass]).to be true
        expect(result[:score]).to eq(65)
      end

      it 'scores maximum (100) with all components maxed' do
        allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(
          { direction: :bullish }
        )
        # body 0.75 → 25, ADX 40 → 20, BOS → 20, range 2.0x → 20, momentum 0.7x → 15 = 100
        candle = build_candle(open: 100.0, high: 118.0, low: 97.0, close: 115.75)
        st = build_supertrend(last_value: 105.0, atr_last: 10.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params.merge(
          series: s, supertrend_result: st, adx_value: 40.0
        ))
        expect(result[:score]).to eq(100)
      end
    end
  end

  describe 'custom min_score threshold' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        entry_quality: {
          enforce: true,
          min_score: 60,
          gates: {
            min_adx: 20,
            block_choppy_regime: true,
            min_body_ratio: 0.40,
            require_momentum_confirm: true
          },
          scoring: {
            candle_body_weight: 25,
            adx_strength_weight: 20,
            bos_weight: 20,
            range_expansion_weight: 20,
            momentum_weight: 15
          },
          index_overrides: {}
        }
      })
    end

    it 'rejects when score is below custom min_score of 60' do
      # ADX 22→5, body 0.45→10, no BOS→0, range < ATR→0, momentum low→3 = 18 (< 60)
      candle = build_candle(open: 100.0, high: 110.0, low: 90.0, close: 109.0)
      st = build_supertrend(last_value: 105.0, atr_last: 25.0)
      s = build_series([candle])
      result = described_class.evaluate(**default_params.merge(
        series: s, supertrend_result: st, adx_value: 22.0
      ))
      expect(result[:pass]).to be false
      expect(result[:reject_reason]).to match(/score_below_threshold/)
    end
  end

  describe 'enforce: false (log-only mode)' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        entry_quality: {
          enforce: false,
          min_score: 40,
          gates: {
            min_adx: 20,
            block_choppy_regime: true,
            min_body_ratio: 0.40,
            require_momentum_confirm: true
          },
          scoring: {
            candle_body_weight: 25,
            adx_strength_weight: 20,
            bos_weight: 20,
            range_expansion_weight: 20,
            momentum_weight: 15
          },
          index_overrides: {}
        }
      })
    end

    it 'always returns pass: true regardless of score' do
      result = described_class.evaluate(**default_params.merge(adx_value: 10.0))
      expect(result[:pass]).to be true
    end

    it 'still reports the actual score and rejection reason' do
      result = described_class.evaluate(**default_params.merge(adx_value: 10.0))
      expect(result[:score]).to eq(0)
      expect(result[:reject_reason]).to eq('min_adx')
    end
  end

  describe 'config absent handling' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({})
    end

    it 'defaults to enforce: false when entry_quality config is missing' do
      result = described_class.evaluate(**default_params.merge(adx_value: 10.0))
      expect(result[:pass]).to be true
    end
  end
```

- [ ] **Step 2: Run tests to verify scoring tests fail**

Run: `bundle exec rspec spec/services/signal/entry_quality_filter_spec.rb`
Expected: Hard gate tests PASS, scoring tests FAIL (placeholder returns min_score, not actual component scores).

- [ ] **Step 3: Commit**

```bash
git add spec/services/signal/entry_quality_filter_spec.rb
git commit -m "test: add scoring and enforce tests for EntryQualityFilter (red)"
```

---

### Task 5: Quality Scoring — Implement

**Files:**
- Modify: `app/services/signal/entry_quality_filter.rb` (replace `calculate_score` placeholder + add enforce logic)

- [ ] **Step 1: Replace the `calculate_score` method and add enforce logic**

In `app/services/signal/entry_quality_filter.rb`, replace the `calculate_score` method and update `evaluate` to handle `enforce: false`:

Replace the `evaluate` method's return block and `calculate_score`:

```ruby
      def evaluate(series:, supertrend_result:, adx_value:, direction:, regime:, index_key:)
        config = load_config(index_key)
        enforce = config[:enforce]
        candles = series&.candles || []

        # Edge case: no data
        if candles.empty?
          result = reject_result('no_candle_data')
          return enforce ? result : result.merge(pass: true)
        end
        if supertrend_result.nil?
          result = reject_result('no_supertrend_data')
          return enforce ? result : result.merge(pass: true)
        end

        # Phase 1: Hard gates
        gate_result = check_gates(candles, supertrend_result, adx_value, direction, regime, config)
        unless gate_result[:pass]
          log_result(index_key, direction, gate_result, nil, false)
          return enforce ? gate_result : gate_result.merge(pass: true)
        end

        # Phase 2: Scoring
        score_result = calculate_score(candles, supertrend_result, adx_value, direction, series, config)

        pass = score_result[:score] >= config[:min_score]
        log_result(index_key, direction, gate_result, score_result, pass)

        result = {
          pass: pass,
          score: score_result[:score],
          gates: gate_result[:gates],
          breakdown: score_result[:breakdown],
          reject_reason: pass ? nil : "score_below_threshold (#{score_result[:score]} < #{config[:min_score]})"
        }

        enforce ? result : result.merge(pass: true)
      end
```

Replace `calculate_score`:

```ruby
      def calculate_score(candles, supertrend_result, adx_value, direction, series, config)
        scoring = config[:scoring]
        breakdown = {}

        candle = candles.last
        range = candle.high - candle.low
        body_ratio = range > 0 ? (candle.close - candle.open).abs / range : 0.0

        # Component 1: Candle body strength (0 - candle_body_weight)
        max_body = scoring[:candle_body_weight]
        breakdown[:candle_body] = if body_ratio >= 0.70
                                    max_body
                                  elsif body_ratio >= 0.55
                                    (max_body * 0.72).round
                                  elsif body_ratio >= 0.40
                                    (max_body * 0.40).round
                                  else
                                    0
                                  end

        # Component 2: ADX strength bonus (0 - adx_strength_weight)
        max_adx = scoring[:adx_strength_weight]
        adx = adx_value.to_f
        breakdown[:adx_strength] = if adx >= 35
                                      max_adx
                                    elsif adx >= 25
                                      (max_adx * 0.60).round
                                    elsif adx >= 20
                                      (max_adx * 0.25).round
                                    else
                                      0
                                    end

        # Component 3: Break of structure (0 - bos_weight)
        max_bos = scoring[:bos_weight]
        breakdown[:bos] = score_bos(series, direction, candles, max_bos)

        # Component 4: Range expansion (0 - range_expansion_weight)
        max_range = scoring[:range_expansion_weight]
        atr_value = current_atr(supertrend_result)
        breakdown[:range_expansion] = if atr_value.nil? || atr_value <= 0
                                        0
                                      elsif range >= 1.5 * atr_value
                                        max_range
                                      elsif range >= 1.2 * atr_value
                                        (max_range * 0.60).round
                                      elsif range >= 1.0 * atr_value
                                        (max_range * 0.25).round
                                      else
                                        0
                                      end

        # Component 5: Momentum confirmation strength (0 - momentum_weight)
        max_momentum = scoring[:momentum_weight]
        breakdown[:momentum] = score_momentum(candle, supertrend_result, direction, atr_value, max_momentum)

        total = breakdown.values.sum
        { score: total, breakdown: breakdown }
      end

      def score_bos(series, direction, candles, max_points)
        # Try BosExtractor first
        bos = begin
          Entries::BosExtractor.last_confirmed_bos(series)
        rescue StandardError
          nil
        end

        if bos && bos[:direction] == direction
          return max_points
        end

        # Fallback: simple structure check (last 3 candles)
        if candles.length >= 3
          last3 = candles.last(3)
          if direction == :bullish
            rising = last3[0].high < last3[1].high && last3[1].high < last3[2].high
            return (max_points * 0.50).round if rising
          else
            falling = last3[0].low > last3[1].low && last3[1].low > last3[2].low
            return (max_points * 0.50).round if falling
          end
        end

        0
      end

      def score_momentum(candle, supertrend_result, direction, atr_value, max_points)
        if atr_value.nil? || atr_value <= 0
          return (max_points * 0.20).round  # minimum 3 for weight 15
        end

        st_value = supertrend_result[:last_value].to_f
        distance = if direction == :bullish
                     (candle.close - st_value) / atr_value
                   else
                     (st_value - candle.close) / atr_value
                   end

        if distance >= 0.5
          max_points
        elsif distance >= 0.25
          (max_points * 0.67).round
        else
          (max_points * 0.20).round
        end
      end

      def current_atr(supertrend_result)
        atr_array = supertrend_result[:atr]
        return nil unless atr_array.is_a?(Array)
        atr_array.compact.last
      end
```

- [ ] **Step 2: Run all tests**

Run: `bundle exec rspec spec/services/signal/entry_quality_filter_spec.rb`
Expected: ALL tests PASS.

- [ ] **Step 3: Commit**

```bash
git add app/services/signal/entry_quality_filter.rb
git commit -m "feat: implement quality scoring system for EntryQualityFilter"
```

---

## Chunk 2: Engine Integration

### Task 6: Signal::Engine Integration — Write Tests

**Files:**
- The integration is tested via the existing signal engine specs. However, we add a focused integration test.
- Create: `spec/services/signal/engine_entry_quality_integration_spec.rb`

- [ ] **Step 1: Write integration test verifying the filter is called**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signal::Engine entry quality filter integration' do
  it 'has EntryQualityFilter.evaluate wired into the signal engine' do
    source = File.read(Rails.root.join('app/services/signal/engine.rb'))
    expect(source).to include('Signal::EntryQualityFilter.evaluate')
  end

  it 'stores quality score in entry_metadata' do
    source = File.read(Rails.root.join('app/services/signal/engine.rb'))
    expect(source).to include('entry_quality_score')
    expect(source).to include('entry_quality_breakdown')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/signal/engine_entry_quality_integration_spec.rb`
Expected: FAIL — `EntryQualityFilter.evaluate` not found in source yet.

- [ ] **Step 3: Commit**

```bash
git add spec/services/signal/engine_entry_quality_integration_spec.rb
git commit -m "test: add integration test for EntryQualityFilter in Signal::Engine (red)"
```

---

### Task 7: Signal::Engine Integration — Implement

**Files:**
- Modify: `app/services/signal/engine.rb`
  - Insert filter call ONCE in shared code (after line 294, before line 296)

**Important context:** Both code paths (Supertrend-only and multi-indicator) converge at line 290 where `validation_result[:valid]` is checked. The shared code after line 294 has `primary_series`, `primary_analysis[:supertrend]`, `primary_analysis[:adx_value]`, `final_direction`, `regime`, and `index_cfg` available from both paths. By inserting the filter here ONCE, we avoid duplicate calls.

- [ ] **Step 1: Add the filter call in shared code after validation check**

After line 294 (the `return` inside `unless validation_result[:valid]`), before line 296 (`permission = :exit_testing`), add:

```ruby
        # ===== ENTRY QUALITY FILTER =====
        quality_result = Signal::EntryQualityFilter.evaluate(
          series: primary_series,
          supertrend_result: primary_analysis[:supertrend],
          adx_value: primary_analysis[:adx_value],
          direction: final_direction,
          regime: regime,
          index_key: index_cfg[:key]
        )
        unless quality_result[:pass]
          Rails.logger.info("[Signal] EntryQualityFilter REJECTED #{index_cfg[:key]} #{final_direction}: #{quality_result[:reject_reason]} (score=#{quality_result[:score]})")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end
        Rails.logger.info("[Signal] EntryQualityFilter PASSED #{index_cfg[:key]} #{final_direction} score=#{quality_result[:score]} #{quality_result[:breakdown]}")
        # ===== END ENTRY QUALITY FILTER =====
```

- [ ] **Step 2: Store quality result in entry_metadata**

Find the `entry_metadata` merge near line 495 (the `diagnostic_metadata.merge` call) and add the quality score:

```ruby
        entry_metadata = diagnostic_metadata.merge(
          entry_contract: supertrend_direct_entry ? 'supertrend_machine_v1' : 'bos_machine_v1',
          permission: execution_permission,
          entry_quality_score: quality_result[:score],
          entry_quality_breakdown: quality_result[:breakdown]
        )
```

- [ ] **Step 3: Run integration test**

Run: `bundle exec rspec spec/services/signal/engine_entry_quality_integration_spec.rb`
Expected: PASS — source now contains `Signal::EntryQualityFilter.evaluate`.

- [ ] **Step 4: Run full filter spec**

Run: `bundle exec rspec spec/services/signal/entry_quality_filter_spec.rb`
Expected: ALL PASS.

- [ ] **Step 5: Run existing signal engine specs (regression check)**

Run: `bundle exec rspec spec/services/signal/`
Expected: No new failures introduced.

- [ ] **Step 6: Commit**

```bash
git add app/services/signal/engine.rb spec/services/signal/engine_entry_quality_integration_spec.rb
git commit -m "feat: integrate EntryQualityFilter into Signal::Engine both code paths"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Run full test suite for signal and entry quality**

Run: `bundle exec rspec spec/services/signal/ --format documentation`
Expected: All EntryQualityFilter tests pass. No regressions in existing signal specs.

- [ ] **Step 2: Run rubocop on modified files**

Run: `bundle exec rubocop app/services/signal/entry_quality_filter.rb app/services/signal/engine.rb`
Expected: No offenses. Fix any issues.

- [ ] **Step 3: Verify config loads in Rails context**

Run: `bundle exec rails runner "cfg = AlgoConfig.fetch[:entry_quality]; puts cfg.inspect; puts 'enforce=' + cfg[:enforce].to_s"`
Expected: Config hash printed, `enforce=true`.

- [ ] **Step 4: Final commit (if any rubocop fixes)**

```bash
git add -A
git commit -m "fix: rubocop cleanup for entry quality filter"
```
