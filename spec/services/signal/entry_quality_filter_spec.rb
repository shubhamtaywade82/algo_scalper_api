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
