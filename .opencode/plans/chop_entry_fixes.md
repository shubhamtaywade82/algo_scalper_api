# Chop Entry Prevention — Implementation Plan

## Problem
Two consecutive losing trades (SENSEX PE -₹1,484, NIFTY PE -₹806) at 12:58-12:59 IST during `chop_decay` regime. MomentumGateGuard is broken and disabled. ChopScore threshold allows moderate chop entries.

## Changes

### 1. Fix MomentumGateGuard — `app/services/entries/guards/momentum_gate_guard.rb`

Replace entire file:

```ruby
# frozen_string_literal: true

module Entries
  module Guards
    class MomentumGateGuard
      include BaseGuard

      DEFAULT_ADX_THRESHOLD = 25

      def self.call(context)
        return PASS unless enabled?

        index_key = (context[:index_cfg] || {})[:key].to_s.upcase
        return PASS if index_key.blank?

        instrument = context[:instrument]
        return PASS unless instrument

        series_15m = instrument.candle_series(interval: '15')
        return PASS unless series_15m&.candles&.size&.>= 20

        bb_pass = bb_breakout?(series_15m)
        adx_pass = adx_strong?(series_15m)

        return PASS if bb_pass
        return PASS if adx_pass

        { blocked: "No momentum: BB breakout=false, ADX=#{format_adx(series_15m)} (threshold: #{adx_threshold})" }
      rescue StandardError => e
        Rails.logger.warn("[MomentumGateGuard] Error: #{e.class} - #{e.message}")
        PASS
      end

      def self.enabled?
        cfg = AlgoConfig.fetch.dig(:risk, :momentum_gate) || {}
        cfg.fetch(:enabled, false)
      end

      def self.bb_breakout?(series)
        detector = MarketRegimeDetector.new(series)
        detector.bollinger_band_breakout?
      rescue StandardError
        false
      end

      def self.adx_strong?(series)
        adx = series.adx(14)
        adx && adx.to_f >= adx_threshold
      rescue StandardError
        false
      end

      def self.adx_threshold
        cfg = AlgoConfig.fetch.dig(:risk, :momentum_gate) || {}
        (cfg[:adx_threshold] || DEFAULT_ADX_THRESHOLD).to_f
      end

      def self.format_adx(series)
        adx = series.adx(14)
        adx ? adx.round(1) : 'N/A'
      rescue StandardError
        'N/A'
      end
    end
  end
end
```

**What changed:**
- `bb_breakout?` now takes a `CandleSeries` and passes it to `MarketRegimeDetector.new(series)` — fixing the constructor bug
- Removed dead `orb_breakout?` (class doesn't exist)
- Added `adx_strong?` fallback — blocks when ADX(14) < 25 on 15-min series
- All errors rescue gracefully to `PASS` (fail-open)

### 2. Enable MomentumGate + lower ChopScore — `config/algo.yml`

**Add after `volume_velocity_gate:` block (line 369):**

```yaml
  momentum_gate:
    enabled: true
    adx_threshold: 25
```

**Change `chop_score:` block (lines 1013-1024) — lower `block_threshold` from 5 to 4:**

```yaml
  chop_score:
    enabled: true
    block_threshold: 4
    caution_threshold: 3
    adx_threshold: 20.0
    supertrend_flip_limit: 3
    supertrend_window_candles: 15
    opening_range_min_points:
      NIFTY: 50
      BANKNIFTY: 150
      SENSEX: 150
    bb_width_threshold: 0.005
```

### 3. Create RegimeGuard — `app/services/entries/guards/regime_guard.rb`

New file:

```ruby
# frozen_string_literal: true

module Entries
  module Guards
    # Blocks entries when the market is in a choppy regime without strong
    # directional conviction.  Uses MarketRegimeDetector on 15-min candles.
    #
    # Bypasses when:
    #   - ADX >= configured threshold (trending market)
    #   - Candle data is insufficient (< 20 candles)
    class RegimeGuard
      include BaseGuard

      DEFAULT_ADX_THRESHOLD = 25
      DEFAULT_BLOCK_REGIMES = %w[CHOPPY].freeze

      def self.call(context)
        cfg = config
        return PASS unless cfg.fetch(:enabled, false)

        index_key = (context[:index_cfg] || {})[:key].to_s.upcase
        return PASS if index_key.blank?

        instrument = context[:instrument]
        return PASS unless instrument

        series_15m = instrument.candle_series(interval: '15')
        return PASS unless series_15m&.candles&.size&.>= 20

        regime_data = detect_regime(series_15m)
        return PASS unless regime_data

        regime = regime_data[:regime].to_s.upcase
        block_regimes = cfg[:block_regimes] || DEFAULT_BLOCK_REGIMES
        return PASS unless block_regimes.include?(regime)

        adx = series_15m.adx(14).to_f
        bypass_adx = (cfg[:bypass_adx] || DEFAULT_ADX_THRESHOLD).to_f
        return PASS if adx >= bypass_adx

        { blocked: "Regime #{regime} (ADX=#{adx.round(1)} < #{bypass_adx}) blocks entry" }
      rescue StandardError => e
        Rails.logger.warn("[RegimeGuard] Error: #{e.class} - #{e.message}")
        PASS
      end

      def self.config
        AlgoConfig.fetch.dig(:risk, :regime_guard) || {}
      rescue StandardError
        {}
      end

      def self.detect_regime(series)
        MarketRegimeDetector.new(series).detect
      rescue StandardError
        nil
      end
    end
  end
end
```

### 4. Register RegimeGuard — `app/services/entries/entry_guard_pipeline.rb`

Insert `Guards::RegimeGuard` after `Guards::MiddayQualityGuard` (line 48):

```ruby
        Guards::MiddayQualityGuard,
        Guards::RegimeGuard,
        Guards::ChopScoreGuard,
```

### 5. Add RegimeGuard config — `config/algo.yml`

Add after `momentum_gate:` block:

```yaml
  regime_guard:
    enabled: true
    block_regimes:
      - CHOPPY
    bypass_adx: 25
```

## Verification

```bash
bundle exec rspec spec/services/live/risk_manager_service_spec.rb
bundle exec rubocop app/services/entries/guards/
```
