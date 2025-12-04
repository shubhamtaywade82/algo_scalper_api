# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::NoTradeEngine do
  describe '.validate' do
    let(:ctx) { OpenStruct.new }

    context 'when score is below threshold (score < 3)' do
      it 'allows trade when no conditions are triggered' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.allowed).to be true
        expect(result.score).to eq(0)
        expect(result.reasons).to be_empty
      end

      it 'allows trade when only 1 condition is triggered' do
        ctx.adx_5m = 14 # Weak trend
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.allowed).to be true
        expect(result.score).to eq(1)
        expect(result.reasons).to include('Weak trend: ADX < 15')
      end

      it 'allows trade when only 2 conditions are triggered' do
        ctx.adx_5m = 14 # Weak trend
        ctx.plus_di_5m = 20
        ctx.minus_di_5m = 19 # DI overlap
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.allowed).to be true
        expect(result.score).to eq(2)
        expect(result.reasons).to include('Weak trend: ADX < 15')
        expect(result.reasons).to include('DI overlap: no directional strength')
      end
    end

    context 'when score reaches threshold (score >= 3)' do
      it 'blocks trade when 3 conditions are triggered' do
        ctx.adx_5m = 14 # Weak trend
        ctx.plus_di_5m = 20
        ctx.minus_di_5m = 19 # DI overlap
        ctx.bos_present = false # No BOS
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.allowed).to be false
        expect(result.score).to eq(3)
        expect(result.reasons).to include('Weak trend: ADX < 15')
        expect(result.reasons).to include('DI overlap: no directional strength')
        expect(result.reasons).to include('No BOS in last 10m')
      end

      it 'blocks trade when multiple conditions are triggered' do
        ctx.adx_5m = 12 # Weak trend
        ctx.plus_di_5m = 20
        ctx.minus_di_5m = 19 # DI overlap
        ctx.bos_present = false # No BOS
        ctx.in_opposite_ob = true # Inside opposite OB
        ctx.inside_fvg = false
        ctx.near_vwap = true # Near VWAP
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.05 # Low volatility
        ctx.atr_downtrend = true # ATR decreasing
        ctx.ce_oi_up = true # Both CE & PE OI rising
        ctx.pe_oi_up = true
        ctx.iv = 8 # Low IV
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = true # Wide spread
        ctx.avg_wick_ratio = 2.0 # High wick ratio
        ctx.time = '09:16' # First 3 minutes
        ctx.time_between = ->(start, _end) { start == '09:15' }

        result = described_class.validate(ctx)

        expect(result.allowed).to be false
        expect(result.score).to be >= 3
        expect(result.reasons.size).to be >= 3
      end
    end

    describe 'trend weakness checks' do
      it 'blocks when ADX < 15' do
        ctx.adx_5m = 14
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Weak trend: ADX < 15')
      end

      it 'allows when ADX >= 15' do
        ctx.adx_5m = 15
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).not_to include('Weak trend: ADX < 15')
      end

      it 'blocks when DI overlap < 2' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 20
        ctx.minus_di_5m = 19 # Difference = 1
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('DI overlap: no directional strength')
      end

      it 'allows when DI difference >= 2' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 20 # Difference = 5
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).not_to include('DI overlap: no directional strength')
      end
    end

    describe 'market structure checks' do
      it 'blocks when no BOS present' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = false
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('No BOS in last 10m')
      end

      it 'blocks when inside opposite Order Block' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = true
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Inside opposite OB')
      end

      it 'blocks when inside opposing FVG' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = true
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Inside opposing FVG')
      end
    end

    describe 'VWAP checks' do
      it 'blocks when near VWAP' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = true
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('VWAP magnet zone')
      end

      it 'blocks when trapped between VWAP and AVWAP' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = true
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Trapped between VWAP & AVWAP')
      end
    end

    describe 'volatility checks' do
      it 'blocks when 10-minute range < 0.1%' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.05
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Low volatility: 10m range < 0.1%')
      end

      it 'blocks when ATR is trending down' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = true
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('ATR decreasing (volatility compression)')
      end
    end

    describe 'option chain checks' do
      it 'blocks when both CE & PE OI are rising' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = true
        ctx.pe_oi_up = true
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Both CE & PE OI rising (writers controlling)')
      end

      it 'blocks when IV is too low' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 8
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include(match(/IV too low/))
      end

      it 'blocks when IV is falling' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = true
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('IV decreasing')
      end

      it 'blocks when spread is wide' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = true
        ctx.avg_wick_ratio = 1.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Wide bid-ask spread')
      end
    end

    describe 'candle quality checks' do
      it 'blocks when wick ratio > 1.8' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 2.0
        ctx.time = '10:30'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include(match(/High wick ratio/))
      end
    end

    describe 'time window checks' do
      it 'blocks during first 3 minutes (09:15-09:18)' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '09:16'
        ctx.time_between = ->(start, _end) { start == '09:15' }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Avoid first 3 minutes')
      end

      it 'blocks during lunch-time if ADX < 20' do
        ctx.adx_5m = 18 # Weak trend
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '12:00'
        ctx.time_between = ->(start, _end) { start == '11:20' }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Lunch-time theta zone (weak trend)')
      end

      it 'allows during lunch-time if ADX >= 20' do
        ctx.adx_5m = 20 # Strong trend
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '12:00'
        ctx.time_between = ->(start, _end) { start == '11:20' }

        result = described_class.validate(ctx)

        expect(result.reasons).not_to include('Lunch-time theta zone (weak trend)')
      end

      it 'blocks after 3:05 PM' do
        ctx.adx_5m = 20
        ctx.plus_di_5m = 25
        ctx.minus_di_5m = 10
        ctx.bos_present = true
        ctx.in_opposite_ob = false
        ctx.inside_fvg = false
        ctx.near_vwap = false
        ctx.trapped_between_vwap = false
        ctx.range_10m_pct = 0.5
        ctx.atr_downtrend = false
        ctx.ce_oi_up = false
        ctx.pe_oi_up = false
        ctx.iv = 15
        ctx.min_iv_threshold = 10
        ctx.iv_falling = false
        ctx.spread_wide = false
        ctx.avg_wick_ratio = 1.0
        ctx.time = '15:10'
        ctx.time_between = ->(_start, _end) { false }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Post 3:05 PM - theta crush')
      end
    end
  end
end
