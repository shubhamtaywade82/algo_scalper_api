# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::EntryQualityFilter do
  # --- Helpers ---

  def build_candle(open:, high:, low:, close:, time: Time.current)
    OpenStruct.new(open: open, high: high, low: low, close: close, time: time)
  end

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
  let(:supertrend_result) { build_supertrend(last_value: 105.0, atr_last: 10.0) }
  let(:series) { build_series([strong_candle]) }
  # Default valid inputs (bullish flip with strong candle)
  let(:strong_candle) { build_candle(open: 100.0, high: 115.0, low: 95.0, close: 112.0) }

  before do
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
    allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(nil)
  end

  describe 'session-aware overrides' do
    let(:base_config) do
      {
        entry_quality: {
          enforce: true,
          min_score: 55,
          gates: { min_adx: 25, block_choppy_regime: true, min_body_ratio: 0.40, require_momentum_confirm: true },
          scoring: {
            candle_body_weight: 25,
            adx_strength_weight: 20,
            bos_weight: 20,
            range_expansion_weight: 20,
            momentum_weight: 15
          },
          session_overrides: {
            chop_decay: { min_score: 60, gates: { min_adx: 30 } }
          },
          index_overrides: {}
        },
        risk: {
          time_regimes: {
            open_expansion: { start: '09:15', end: '09:45' },
            trend_continuation: { start: '09:45', end: '11:30' },
            chop_decay: { start: '11:30', end: '13:45' },
            close_gamma: { start: '13:45', end: '15:15' }
          }
        }
      }
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(base_config)
      allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(nil)
    end

    context 'during chop_decay session (12:00 IST)' do
      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-16 12:00:00 +05:30'))
      end

      it 'applies chop_decay session overrides (min_adx: 30)' do
        result = described_class.evaluate(
          series: series,
          supertrend_result: supertrend_result,
          adx_value: 27,
          direction: :bullish,
          regime: 'TRENDING',
          index_key: 'NIFTY'
        )
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('min_adx')
      end

      it 'loads config with overridden min_score and min_adx' do
        config = described_class.send(:load_config, 'NIFTY')
        expect(config[:min_score]).to eq(60)
        expect(config[:gates][:min_adx]).to eq(30)
      end
    end

    context 'during trend_continuation session (10:00 IST)' do
      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-16 10:00:00 +05:30'))
      end

      it 'uses standard thresholds (min_adx: 25)' do
        result = described_class.evaluate(
          series: series,
          supertrend_result: supertrend_result,
          adx_value: 27,
          direction: :bullish,
          regime: 'TRENDING',
          index_key: 'NIFTY'
        )
        expect(result[:reject_reason]).not_to eq('min_adx')
      end
    end
  end

  def build_series(candles)
    series = instance_double(CandleSeries)
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

  describe 'hard gates' do
    context 'Gate 1: ADX minimum' do
      it 'rejects when ADX < 20' do
        result = described_class.evaluate(**default_params, adx_value: 17.0)
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('min_adx')
        expect(result[:gates][:adx]).to be false
      end

      it 'passes when ADX == 20' do
        result = described_class.evaluate(**default_params, adx_value: 20.0)
        expect(result[:gates][:adx]).to be true
      end

      it 'passes when ADX > 20' do
        result = described_class.evaluate(**default_params, adx_value: 25.0)
        expect(result[:gates][:adx]).to be true
      end

      it 'rejects nil ADX' do
        result = described_class.evaluate(**default_params, adx_value: nil)
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('min_adx')
      end
    end

    context 'Gate 2: Regime not CHOPPY' do
      it 'rejects CHOPPY regime' do
        result = described_class.evaluate(**default_params, regime: 'CHOPPY')
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('regime')
        expect(result[:gates][:regime]).to be false
      end

      it 'passes RANGING regime' do
        result = described_class.evaluate(**default_params, regime: 'RANGING')
        expect(result[:gates][:regime]).to be true
      end

      it 'passes TRENDING_UP regime' do
        result = described_class.evaluate(**default_params, regime: 'TRENDING_UP')
        expect(result[:gates][:regime]).to be true
      end

      it 'handles symbol input gracefully' do
        result = described_class.evaluate(**default_params, regime: :choppy)
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('regime')
      end
    end

    context 'Gate 3: Candle body ratio' do
      it 'rejects doji candle (body_ratio 0.1)' do
        doji = build_candle(open: 100.0, high: 110.0, low: 90.0, close: 102.0)
        s = build_series([doji])
        result = described_class.evaluate(**default_params, series: s)
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('body_ratio')
        expect(result[:gates][:body_ratio]).to be false
      end

      it 'passes strong candle (body_ratio 0.6)' do
        candle = build_candle(open: 100.0, high: 115.0, low: 95.0, close: 112.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params, series: s)
        expect(result[:gates][:body_ratio]).to be true
      end

      it 'rejects zero-range candle (high == low)' do
        flat = build_candle(open: 100.0, high: 100.0, low: 100.0, close: 100.0)
        s = build_series([flat])
        result = described_class.evaluate(**default_params, series: s)
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('body_ratio')
      end
    end

    context 'Gate 4: Momentum confirmation' do
      it 'rejects bullish flip when close < supertrend' do
        # body_ratio = |104 - 95| / (110 - 95) = 9/15 = 0.60 (passes body gate)
        # but close 104 < supertrend 105 (fails momentum)
        candle = build_candle(open: 95.0, high: 110.0, low: 95.0, close: 104.0)
        st = build_supertrend(last_value: 105.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params, series: s, supertrend_result: st)
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('momentum')
        expect(result[:gates][:momentum]).to be false
      end

      it 'passes bullish flip when close > supertrend' do
        result = described_class.evaluate(**default_params)
        expect(result[:gates][:momentum]).to be true
      end

      it 'rejects bearish flip when close > supertrend' do
        # body_ratio = |110 - 98| / (115 - 90) = 12/25 = 0.48 (passes body gate)
        # but close 110 > supertrend 105 (fails bearish momentum)
        candle = build_candle(open: 98.0, high: 115.0, low: 90.0, close: 110.0)
        st = build_supertrend(last_value: 105.0, trend: :bearish)
        s = build_series([candle])
        result = described_class.evaluate(**default_params, series: s, supertrend_result: st, direction: :bearish)
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('momentum')
      end

      it 'passes bearish flip when close < supertrend' do
        candle = build_candle(open: 110.0, high: 115.0, low: 90.0, close: 98.0)
        st = build_supertrend(last_value: 105.0, trend: :bearish)
        s = build_series([candle])
        result = described_class.evaluate(**default_params, series: s, supertrend_result: st, direction: :bearish)
        expect(result[:gates][:momentum]).to be true
      end
    end

    context 'edge cases' do
      it 'rejects nil series gracefully' do
        result = described_class.evaluate(**default_params, series: nil)
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('no_candle_data')
      end

      it 'rejects empty candles gracefully' do
        s = build_series([])
        result = described_class.evaluate(**default_params, series: s)
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('no_candle_data')
      end

      it 'rejects nil supertrend_result gracefully' do
        result = described_class.evaluate(**default_params, supertrend_result: nil)
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to eq('no_supertrend_data')
      end
    end
  end

  describe 'index overrides' do
    it 'uses SENSEX min_adx override of 22' do
      result = described_class.evaluate(**default_params, index_key: 'SENSEX', adx_value: 21.0)
      expect(result[:pass]).to be false
      expect(result[:reject_reason]).to eq('min_adx')
    end

    it 'passes SENSEX when ADX >= 22' do
      result = described_class.evaluate(**default_params, index_key: 'SENSEX', adx_value: 22.0)
      expect(result[:gates][:adx]).to be true
    end
  end

  describe 'quality scoring' do
    context 'Component 1: Candle body strength (0-25)' do
      it 'scores 10 for body_ratio 0.40-0.55' do
        # body_ratio = |109 - 100| / (110 - 90) = 9/20 = 0.45
        candle = build_candle(open: 100.0, high: 110.0, low: 90.0, close: 109.0)
        st = build_supertrend(last_value: 105.0, atr_last: 20.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params, series: s, supertrend_result: st)
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
        result = described_class.evaluate(**default_params, series: s, supertrend_result: st)
        expect(result[:breakdown][:candle_body]).to eq(25)
      end
    end

    context 'Component 2: ADX strength bonus (0-20)' do
      it 'scores 5 for ADX 20-25' do
        result = described_class.evaluate(**default_params, adx_value: 22.0)
        expect(result[:breakdown][:adx_strength]).to eq(5)
      end

      it 'scores 12 for ADX 25-35' do
        result = described_class.evaluate(**default_params, adx_value: 30.0)
        expect(result[:breakdown][:adx_strength]).to eq(12)
      end

      it 'scores 20 for ADX >= 35' do
        result = described_class.evaluate(**default_params, adx_value: 40.0)
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
        c1 = build_candle(open: 95.0, high: 100.0, low: 90.0, close: 98.0, time: 1.minute.ago)
        c2 = build_candle(open: 98.0, high: 105.0, low: 93.0, close: 103.0, time: 30.seconds.ago)
        c3 = build_candle(open: 100.0, high: 115.0, low: 95.0, close: 112.0)
        s = build_series([c1, c2, c3])
        result = described_class.evaluate(**default_params, series: s)
        expect(result[:breakdown][:bos]).to eq(10)
      end

      it 'scores 0 when no structure confirmation' do
        result = described_class.evaluate(**default_params)
        expect(result[:breakdown][:bos]).to eq(0)
      end
    end

    context 'Component 4: Range expansion (0-20)' do
      it 'scores 20 when range >= 1.5x ATR' do
        # range = 115 - 95 = 20, ATR = 10 -> 2.0x
        result = described_class.evaluate(**default_params)
        expect(result[:breakdown][:range_expansion]).to eq(20)
      end

      it 'scores 12 when range >= 1.2x ATR' do
        # range = 115 - 95 = 20, ATR = 15 -> 1.33x
        st = build_supertrend(last_value: 105.0, atr_last: 15.0)
        result = described_class.evaluate(**default_params, supertrend_result: st)
        expect(result[:breakdown][:range_expansion]).to eq(12)
      end

      it 'scores 5 when range >= 1.0x ATR' do
        # range = 115 - 95 = 20, ATR = 18 -> 1.11x
        st = build_supertrend(last_value: 105.0, atr_last: 18.0)
        result = described_class.evaluate(**default_params, supertrend_result: st)
        expect(result[:breakdown][:range_expansion]).to eq(5)
      end

      it 'scores 0 when range < 1.0x ATR' do
        # range = 115 - 95 = 20, ATR = 25 -> 0.80x
        st = build_supertrend(last_value: 105.0, atr_last: 25.0)
        result = described_class.evaluate(**default_params, supertrend_result: st)
        expect(result[:breakdown][:range_expansion]).to eq(0)
      end

      it 'scores 0 when ATR is zero' do
        st = build_supertrend(last_value: 105.0, atr_last: 0.0)
        result = described_class.evaluate(**default_params, supertrend_result: st)
        expect(result[:breakdown][:range_expansion]).to eq(0)
      end

      it 'scores 0 when ATR is nil' do
        st = { trend: :bullish, last_value: 105.0, atr: [nil, nil, nil], line: [nil, nil, 105.0] }
        result = described_class.evaluate(**default_params, supertrend_result: st)
        expect(result[:breakdown][:range_expansion]).to eq(0)
      end
    end

    context 'Component 5: Momentum confirmation strength (0-15)' do
      it 'scores 15 when distance >= 0.5x ATR' do
        # distance = (112 - 105) / 10 = 0.7
        result = described_class.evaluate(**default_params)
        expect(result[:breakdown][:momentum]).to eq(15)
      end

      it 'scores 10 when distance >= 0.25x ATR' do
        # distance = (108 - 105) / 10 = 0.3
        candle = build_candle(open: 100.0, high: 115.0, low: 95.0, close: 108.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params, series: s)
        expect(result[:breakdown][:momentum]).to eq(10)
      end

      it 'scores 3 when distance < 0.25x ATR' do
        # body_ratio = |106 - 95| / (115 - 95) = 11/20 = 0.55 (passes body gate)
        # distance = (106 - 105) / 10 = 0.1 (< 0.25)
        candle = build_candle(open: 95.0, high: 115.0, low: 95.0, close: 106.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params, series: s)
        expect(result[:breakdown][:momentum]).to eq(3)
      end

      it 'scores 3 when ATR is zero (minimum since momentum gate passed)' do
        st = build_supertrend(last_value: 105.0, atr_last: 0.0)
        result = described_class.evaluate(**default_params, supertrend_result: st)
        expect(result[:breakdown][:momentum]).to eq(3)
      end

      it 'scores bearish distance correctly' do
        # bearish: distance = (105 - 92) / 10 = 1.3
        candle = build_candle(open: 110.0, high: 115.0, low: 90.0, close: 92.0)
        st = build_supertrend(last_value: 105.0, trend: :bearish)
        s = build_series([candle])
        result = described_class.evaluate(**default_params, series: s, supertrend_result: st, direction: :bearish)
        expect(result[:breakdown][:momentum]).to eq(15)
      end
    end

    context 'threshold' do
      it 'fails when total score < min_score (40)' do
        # ADX 20->5, body 0.45->10, no BOS->0, range<ATR->0, momentum low->3 = 18
        candle = build_candle(open: 100.0, high: 110.0, low: 90.0, close: 109.0)
        st = build_supertrend(last_value: 105.0, atr_last: 25.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params, series: s, supertrend_result: st, adx_value: 20.0)
        expect(result[:pass]).to be false
        expect(result[:reject_reason]).to include('score_below_threshold')
      end

      it 'passes when total score >= min_score (40)' do
        # ADX 25->12, body 0.60->18, no BOS->0, range 2.0x->20, momentum 0.7x->15 = 65
        result = described_class.evaluate(**default_params)
        expect(result[:pass]).to be true
        expect(result[:score]).to eq(65)
      end

      it 'scores maximum (100) with all components maxed' do
        allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(
          { direction: :bullish }
        )
        # body 0.75->25, ADX 40->20, BOS->20, range 2.0x->20, momentum 0.7x->15 = 100
        candle = build_candle(open: 100.0, high: 118.0, low: 97.0, close: 115.75)
        st = build_supertrend(last_value: 105.0, atr_last: 10.0)
        s = build_series([candle])
        result = described_class.evaluate(**default_params, series: s, supertrend_result: st, adx_value: 40.0)
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
      # ADX 22->5, body 0.45->10, no BOS->0, range<ATR->0, momentum low->3 = 18 (< 60)
      candle = build_candle(open: 100.0, high: 110.0, low: 90.0, close: 109.0)
      st = build_supertrend(last_value: 105.0, atr_last: 25.0)
      s = build_series([candle])
      result = described_class.evaluate(**default_params, series: s, supertrend_result: st, adx_value: 22.0)
      expect(result[:pass]).to be false
      expect(result[:reject_reason]).to include('score_below_threshold')
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
      result = described_class.evaluate(**default_params, adx_value: 10.0)
      expect(result[:pass]).to be true
    end

    it 'still reports the actual score and rejection reason' do
      result = described_class.evaluate(**default_params, adx_value: 10.0)
      expect(result[:score]).to eq(0)
      expect(result[:reject_reason]).to eq('min_adx')
    end
  end

  describe 'config absent handling' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({})
    end

    it 'defaults to enforce: false when entry_quality config is missing' do
      result = described_class.evaluate(**default_params, adx_value: 10.0)
      expect(result[:pass]).to be true
    end
  end
end
