# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::EarlyTrendFailure do
  let(:config) do
    {
      risk: {
        etf: {
          enabled: true,
          activation_profit_pct: 7.0,
          trend_score_drop_pct: 30.0,
          adx_collapse_threshold: 10,
          atr_ratio_threshold: 0.55,
          confirmation_ticks: 2
        }
      }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(config)
  end

  describe '.applicable?' do
    it 'returns true when pnl is below activation threshold' do
      expect(described_class.applicable?(5.0)).to be true
      expect(described_class.applicable?(0.0)).to be true
      expect(described_class.applicable?(-5.0)).to be true
    end

    it 'returns false when pnl is above activation threshold' do
      expect(described_class.applicable?(7.0)).to be false
      expect(described_class.applicable?(10.0)).to be false
    end

    it 'respects custom activation_profit_pct' do
      expect(described_class.applicable?(5.0, activation_profit_pct: 3.0)).to be false
      expect(described_class.applicable?(2.0, activation_profit_pct: 3.0)).to be true
    end
  end

  describe '.early_trend_failure?' do
    let(:position_data) do
      data = OpenStruct.new(
        trend_score: 50.0,
        peak_trend_score: 50.0,
        adx: 25.0,
        atr_ratio: 1.0,
        underlying_price: 100.0,
        vwap: 100.0
      )
      data.define_singleton_method(:is_long?) { true }
      data
    end

    context 'when ETF is disabled' do
      before do
        config[:risk][:etf][:enabled] = false
      end

      it 'returns false' do
        expect(described_class.early_trend_failure?(position_data)).to be false
      end
    end

    context 'trend score collapse' do
      it 'triggers when trend score drops significantly' do
        position_data.peak_trend_score = 100.0
        position_data.trend_score = 50.0 # 50% drop

        expect(described_class.early_trend_failure?(position_data)).to be true
      end

      it 'does not trigger for small drops' do
        position_data.peak_trend_score = 100.0
        position_data.trend_score = 80.0 # 20% drop

        expect(described_class.early_trend_failure?(position_data)).to be false
      end

      it 'handles zero peak trend score gracefully' do
        position_data.peak_trend_score = 0.0
        position_data.trend_score = 50.0

        expect(described_class.early_trend_failure?(position_data)).to be false
      end
    end

    context 'ADX collapse' do
      it 'triggers when ADX is below threshold' do
        position_data.adx = 8.0

        expect(described_class.early_trend_failure?(position_data)).to be true
      end

      it 'does not trigger when ADX is above threshold' do
        position_data.adx = 15.0

        expect(described_class.early_trend_failure?(position_data)).to be false
      end

      it 'handles nil ADX gracefully' do
        position_data.adx = nil

        expect(described_class.early_trend_failure?(position_data)).to be false
      end
    end

    context 'ATR ratio collapse' do
      it 'triggers when ATR ratio is below threshold' do
        position_data.atr_ratio = 0.50

        expect(described_class.early_trend_failure?(position_data)).to be true
      end

      it 'does not trigger when ATR ratio is above threshold' do
        position_data.atr_ratio = 0.60

        expect(described_class.early_trend_failure?(position_data)).to be false
      end
    end

    context 'VWAP rejection' do
      it 'triggers for long positions when price moves below VWAP' do
        position_data.define_singleton_method(:is_long?) { true }
        position_data.underlying_price = 95.0
        position_data.vwap = 100.0

        expect(described_class.early_trend_failure?(position_data)).to be true
      end

      it 'does not trigger for long positions when price is above VWAP' do
        position_data.define_singleton_method(:is_long?) { true }
        position_data.underlying_price = 105.0
        position_data.vwap = 100.0

        expect(described_class.early_trend_failure?(position_data)).to be false
      end

      it 'triggers for short positions when price moves above VWAP' do
        position_data.define_singleton_method(:is_long?) { false }
        position_data.underlying_price = 105.0
        position_data.vwap = 100.0

        expect(described_class.early_trend_failure?(position_data)).to be true
      end

      it 'handles zero prices gracefully' do
        position_data.underlying_price = 0.0
        position_data.vwap = 100.0

        expect(described_class.early_trend_failure?(position_data)).to be false
      end
    end

    context 'multiple conditions' do
      it 'triggers if any condition is met' do
        position_data.adx = 8.0 # ADX collapse

        expect(described_class.early_trend_failure?(position_data)).to be true
      end
    end

    context 'error handling' do
      it 'returns false on errors' do
        position_data = nil

        expect(described_class.early_trend_failure?(position_data)).to be false
      end

      it 'handles missing methods gracefully' do
        position_data = OpenStruct.new(foo: 'bar')

        expect(described_class.early_trend_failure?(position_data)).to be false
      end
    end
  end
end
