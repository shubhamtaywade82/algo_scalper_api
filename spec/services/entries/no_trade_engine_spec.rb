# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::NoTradeEngine do
  describe '.validate' do
    let(:ctx) { OpenStruct.new }

    # Helper method to set up default valid context
    def setup_valid_context(index_key: 'NIFTY')
      ctx.index_key = index_key
      ctx.adx_5m = 20
      ctx.plus_di_5m = 25
      ctx.minus_di_5m = 10
      ctx.bos_present = true
      ctx.in_opposite_ob = false
      ctx.inside_fvg = false
      ctx.near_vwap = false
      ctx.trapped_between_vwap = false
      ctx.vwap_chop = false
      ctx.range_10m_pct = 0.5
      ctx.atr_downtrend = false
      ctx.ce_oi_up = false
      ctx.pe_oi_up = false
      ctx.iv = 15
      ctx.min_iv_threshold = index_key == 'NIFTY' ? 10 : (index_key.include?('SENSEX') ? 11 : 10)
      ctx.iv_falling = false
      ctx.spread_wide = false
      ctx.spread_wide_soft = false
      ctx.avg_wick_ratio = 1.0
      ctx.time = '10:30'
      ctx.time_between = ->(_start, _end) { false }
      ctx
    end

    context 'when score is below threshold (score < 3)' do
      it 'allows trade when no conditions are triggered' do
        setup_valid_context

        result = described_class.validate(ctx)

        expect(result.allowed).to be true
        expect(result.score).to eq(0)
        expect(result.reasons).to be_empty
      end

      it 'allows trade when only 1 condition is triggered' do
        setup_valid_context
        ctx.adx_5m = 13 # Weak trend for NIFTY (< 14)

        result = described_class.validate(ctx)

        expect(result.allowed).to be true
        expect(result.score).to be >= 1
        expect(result.reasons).to include(match(/Weak trend: ADX < 14/))
      end

      it 'allows trade when only 2 conditions are triggered' do
        setup_valid_context
        ctx.adx_5m = 13 # Weak trend for NIFTY
        ctx.plus_di_5m = 20
        ctx.minus_di_5m = 19 # DI overlap (< 2 for NIFTY)

        result = described_class.validate(ctx)

        expect(result.allowed).to be true
        expect(result.score).to be >= 2
        expect(result.reasons).to include(match(/Weak trend: ADX < 14/))
        expect(result.reasons).to include(match(/DI overlap: no directional strength/))
      end
    end

    context 'when score reaches threshold (score >= 3)' do
      it 'blocks trade when 3 conditions are triggered' do
        setup_valid_context
        ctx.adx_5m = 13 # Weak trend for NIFTY (< 14)
        ctx.plus_di_5m = 20
        ctx.minus_di_5m = 19 # DI overlap (< 2 for NIFTY)
        ctx.bos_present = false # No BOS

        result = described_class.validate(ctx)

        expect(result.allowed).to be false
        expect(result.score).to be >= 3
        expect(result.reasons).to include(match(/Weak trend: ADX < 14/))
        expect(result.reasons).to include(match(/DI overlap: no directional strength/))
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
      context 'for NIFTY' do
        it 'blocks when ADX < 14' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.adx_5m = 13

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/Weak trend: ADX < 14/))
        end

        it 'applies soft penalty when ADX 14-18' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.adx_5m = 16

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/Moderate trend: ADX.*14-18/))
        end

        it 'allows when ADX >= 18' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.adx_5m = 19

          result = described_class.validate(ctx)

          expect(result.reasons).not_to include(match(/Weak trend|Moderate trend/))
        end

        it 'blocks when DI difference < 2' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.plus_di_5m = 20
          ctx.minus_di_5m = 19 # Difference = 1

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/DI overlap: no directional strength.*diff: 1.0 < 2.0/))
        end
      end

      context 'for SENSEX' do
        it 'blocks when ADX < 12' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.adx_5m = 11

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/Weak trend: ADX < 12/))
        end

        it 'applies soft penalty when ADX 12-16' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.adx_5m = 14

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/Moderate trend: ADX.*12-16/))
        end

        it 'blocks when DI difference < 1.5' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.plus_di_5m = 20
          ctx.minus_di_5m = 19 # Difference = 1

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/DI overlap: no directional strength.*diff: 1.0 < 1.5/))
        end
      end
    end

    describe 'market structure checks' do
      it 'blocks when no BOS present' do
        setup_valid_context
        ctx.bos_present = false

        result = described_class.validate(ctx)

        expect(result.reasons).to include('No BOS in last 10m')
      end

      it 'blocks when inside opposite Order Block' do
        setup_valid_context
        ctx.in_opposite_ob = true

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Inside opposite OB')
      end

      it 'blocks when inside opposing FVG' do
        setup_valid_context
        ctx.inside_fvg = true

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Inside opposing FVG')
      end
    end

    describe 'VWAP checks' do
      it 'blocks when near VWAP' do
        setup_valid_context
        ctx.near_vwap = true

        result = described_class.validate(ctx)

        expect(result.reasons).to include('VWAP magnet zone')
      end

      it 'blocks when trapped between VWAP and AVWAP' do
        setup_valid_context
        ctx.trapped_between_vwap = true

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Trapped between VWAP & AVWAP')
      end

      context 'VWAP chop detection' do
        it 'blocks when VWAP chop detected for NIFTY (3+ candles within ±0.08%)' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.vwap_chop = true

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/VWAP chop: price within ±0.08% for 3\+ candles/))
        end

        it 'blocks when VWAP chop detected for SENSEX (2+ candles within ±0.06%)' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.vwap_chop = true

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/VWAP chop: price within ±0.06% for 2\+ candles/))
        end
      end
    end

    describe 'volatility checks' do
      context 'for NIFTY' do
        it 'blocks when 10-minute range < 0.06%' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.range_10m_pct = 0.05

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/Low volatility: 10m range < 0.06%/))
        end

        it 'applies soft penalty when range 0.06-0.1%' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.range_10m_pct = 0.08

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/Moderate volatility: 10m range.*0.06-0.1/))
        end
      end

      context 'for SENSEX' do
        it 'blocks when 10-minute range < 0.04%' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.range_10m_pct = 0.03

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/Low volatility: 10m range < 0.04%/))
        end

        it 'applies soft penalty when range 0.04-0.08%' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.range_10m_pct = 0.06

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/Moderate volatility: 10m range.*0.04-0.08/))
        end
      end

      it 'blocks when ATR is trending down' do
        setup_valid_context
        ctx.atr_downtrend = true

        result = described_class.validate(ctx)

        expect(result.reasons).to include('ATR decreasing (volatility compression)')
      end
    end

    describe 'option chain checks' do
      context 'OI trap detection' do
        it 'blocks when both CE & PE OI rising AND range below threshold for NIFTY' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.ce_oi_up = true
          ctx.pe_oi_up = true
          ctx.range_10m_pct = 0.07 # Below 0.08% threshold

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/OI trap: Both CE & PE OI rising & range < 0.08%/))
        end

        it 'applies soft penalty when both CE & PE OI rising but range above threshold' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.ce_oi_up = true
          ctx.pe_oi_up = true
          ctx.range_10m_pct = 0.12 # Above 0.08% threshold

          result = described_class.validate(ctx)

          expect(result.reasons).to include('Both CE & PE OI rising (writers controlling)')
        end

        it 'blocks when both CE & PE OI rising AND range below threshold for SENSEX' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.ce_oi_up = true
          ctx.pe_oi_up = true
          ctx.range_10m_pct = 0.05 # Below 0.06% threshold

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/OI trap: Both CE & PE OI rising & range < 0.06%/))
        end
      end

      context 'IV thresholds' do
        it 'blocks when IV < 9 for NIFTY' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.iv = 8
          ctx.min_iv_threshold = 9

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/IV too low: 8.0 < 9/))
        end

        it 'applies soft penalty when IV 9-11 for NIFTY' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.iv = 10
          ctx.min_iv_threshold = 9

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/IV moderate: 10.0.*9-11/))
        end

        it 'blocks when IV < 11 for SENSEX' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.iv = 10
          ctx.min_iv_threshold = 11

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/IV too low: 10.0 < 11/))
        end

        it 'applies soft penalty when IV 11-13 for SENSEX' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.iv = 12
          ctx.min_iv_threshold = 11

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/IV moderate: 12.0.*11-13/))
        end
      end

      it 'blocks when IV is falling' do
        setup_valid_context
        ctx.iv_falling = true

        result = described_class.validate(ctx)

        expect(result.reasons).to include('IV decreasing')
      end

      context 'spread thresholds' do
        it 'blocks when spread is wide (hard threshold) for NIFTY' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.spread_wide = true

          result = described_class.validate(ctx)

          expect(result.reasons).to include('Wide bid-ask spread (hard threshold)')
        end

        it 'applies soft penalty when spread is wide (soft threshold) for NIFTY' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.spread_wide_soft = true

          result = described_class.validate(ctx)

          expect(result.reasons).to include('Wide bid-ask spread (soft threshold)')
        end

        it 'blocks when spread is wide (hard threshold) for SENSEX' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.spread_wide = true

          result = described_class.validate(ctx)

          expect(result.reasons).to include('Wide bid-ask spread (hard threshold)')
        end
      end
    end

    describe 'candle quality checks' do
      context 'for NIFTY' do
        it 'blocks when wick ratio > 2.2' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.avg_wick_ratio = 2.3

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/High wick ratio: 2.3 > 2.2/))
        end

        it 'applies soft penalty when wick ratio 1.8-2.2' do
          setup_valid_context(index_key: 'NIFTY')
          ctx.avg_wick_ratio = 2.0

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/Moderate wick ratio: 2.0.*1.8-2.2/))
        end
      end

      context 'for SENSEX' do
        it 'blocks when wick ratio > 2.5' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.avg_wick_ratio = 2.6

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/High wick ratio: 2.6 > 2.5/))
        end

        it 'applies soft penalty when wick ratio 2.0-2.5' do
          setup_valid_context(index_key: 'SENSEX')
          ctx.avg_wick_ratio = 2.3

          result = described_class.validate(ctx)

          expect(result.reasons).to include(match(/Moderate wick ratio: 2.3.*2.0-2.5/))
        end
      end
    end

    describe 'time window checks' do
      it 'blocks during first 3 minutes (09:15-09:18)' do
        setup_valid_context
        ctx.time = '09:16'
        ctx.time_between = ->(start, _end) { start == '09:15' }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Avoid first 3 minutes')
      end

      it 'blocks during lunch-time if ADX < 20' do
        setup_valid_context
        ctx.adx_5m = 18 # Weak trend
        ctx.time = '12:00'
        ctx.time_between = ->(start, _end) { start == '11:20' }

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Lunch-time theta zone (weak trend)')
      end

      it 'allows during lunch-time if ADX >= 20' do
        setup_valid_context
        ctx.adx_5m = 20 # Strong trend
        ctx.time = '12:00'
        ctx.time_between = ->(start, _end) { start == '11:20' }

        result = described_class.validate(ctx)

        expect(result.reasons).not_to include('Lunch-time theta zone (weak trend)')
      end

      it 'blocks after 3:05 PM' do
        setup_valid_context
        ctx.time = '15:10'

        result = described_class.validate(ctx)

        expect(result.reasons).to include('Post 3:05 PM - theta crush')
      end
    end

    describe 'soft penalty scoring' do
      it 'blocks trade when score >= 2 AND soft_penalties >= 2' do
        setup_valid_context(index_key: 'NIFTY')
        ctx.adx_5m = 16 # Soft penalty (14-18)
        ctx.range_10m_pct = 0.08 # Soft penalty (0.06-0.1)
        ctx.bos_present = false # Hard penalty

        result = described_class.validate(ctx)

        expect(result.allowed).to be false
        expect(result.score).to be >= 2.0
      end
    end
  end
end
