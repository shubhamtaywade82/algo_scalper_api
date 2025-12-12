# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::EarlyTrendFailure, 'configuration variations' do
  describe '.applicable? with different configs' do
    context 'low activation threshold' do
      let(:config) do
        {
          risk: {
            etf: {
              enabled: true,
              activation_profit_pct: 3.0 # Lower threshold
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'applies to more positions' do
        expect(described_class.applicable?(2.0)).to be true
        expect(described_class.applicable?(5.0)).to be false # Above threshold
      end
    end

    context 'high activation threshold' do
      let(:config) do
        {
          risk: {
            etf: {
              enabled: true,
              activation_profit_pct: 10.0 # Higher threshold
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'applies to fewer positions' do
        expect(described_class.applicable?(5.0)).to be true
        expect(described_class.applicable?(12.0)).to be false # Above threshold
      end
    end

    context 'when ETF is disabled' do
      let(:config) do
        {
          risk: {
            etf: {
              enabled: false,
              activation_profit_pct: 7.0
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'still checks applicability' do
        expect(described_class.applicable?(5.0)).to be true
        expect(described_class.applicable?(8.0)).to be false
      end
    end
  end

  describe '.early_trend_failure? with different configs' do
    let(:position_data) do
      OpenStruct.new(
        trend_score: 50.0,
        peak_trend_score: 50.0,
        adx: 25.0,
        atr_ratio: 1.0,
        underlying_price: 100.0,
        vwap: 100.0,
        is_long?: true
      )
    end

    context 'sensitive trend score drop' do
      let(:config) do
        {
          risk: {
            etf: {
              enabled: true,
              trend_score_drop_pct: 20.0 # More sensitive
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'triggers on smaller drops' do
        position_data.peak_trend_score = 100.0
        position_data.trend_score = 75.0 # 25% drop

        expect(described_class.early_trend_failure?(position_data)).to be true
      end
    end

    context 'strict ADX threshold' do
      let(:config) do
        {
          risk: {
            etf: {
              enabled: true,
              adx_collapse_threshold: 15 # Higher threshold
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'triggers on higher ADX values' do
        position_data.adx = 12.0

        expect(described_class.early_trend_failure?(position_data)).to be true
      end
    end

    context 'strict ATR ratio threshold' do
      let(:config) do
        {
          risk: {
            etf: {
              enabled: true,
              atr_ratio_threshold: 0.70 # Higher threshold
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'triggers on higher ATR ratios' do
        position_data.atr_ratio = 0.65

        expect(described_class.early_trend_failure?(position_data)).to be true
      end
    end

    context 'when ETF is disabled' do
      let(:config) do
        {
          risk: {
            etf: {
              enabled: false,
              trend_score_drop_pct: 30.0,
              adx_collapse_threshold: 10,
              atr_ratio_threshold: 0.55
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'returns false regardless of conditions' do
        position_data.peak_trend_score = 100.0
        position_data.trend_score = 50.0 # 50% drop
        position_data.adx = 5.0
        position_data.atr_ratio = 0.40

        expect(described_class.early_trend_failure?(position_data)).to be false
      end
    end

    context 'with missing config values' do
      let(:config) do
        {
          risk: {
            etf: {
              enabled: true
              # Missing thresholds
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'handles gracefully' do
        position_data.peak_trend_score = 100.0
        position_data.trend_score = 50.0

        # Should not crash, may return false if thresholds are nil/zero
        expect { described_class.early_trend_failure?(position_data) }.not_to raise_error
      end
    end
  end

  describe 'multiple condition combinations' do
    let(:config) do
      {
        risk: {
          etf: {
            enabled: true,
            trend_score_drop_pct: 30.0,
            adx_collapse_threshold: 10,
            atr_ratio_threshold: 0.55
          }
        }
      }
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(config)
    end

    context 'only trend score collapse' do
      let(:position_data) do
        OpenStruct.new(
          trend_score: 50.0,
          peak_trend_score: 100.0,
          adx: 25.0,
          atr_ratio: 1.0,
          underlying_price: 100.0,
          vwap: 100.0,
          is_long?: true
        )
      end

      it 'triggers ETF' do
        expect(described_class.early_trend_failure?(position_data)).to be true
      end
    end

    context 'only ADX collapse' do
      let(:position_data) do
        OpenStruct.new(
          trend_score: 50.0,
          peak_trend_score: 50.0,
          adx: 8.0,
          atr_ratio: 1.0,
          underlying_price: 100.0,
          vwap: 100.0,
          is_long?: true
        )
      end

      it 'triggers ETF' do
        expect(described_class.early_trend_failure?(position_data)).to be true
      end
    end

    context 'only ATR collapse' do
      let(:position_data) do
        OpenStruct.new(
          trend_score: 50.0,
          peak_trend_score: 50.0,
          adx: 25.0,
          atr_ratio: 0.50,
          underlying_price: 100.0,
          vwap: 100.0,
          is_long?: true
        )
      end

      it 'triggers ETF' do
        expect(described_class.early_trend_failure?(position_data)).to be true
      end
    end

    context 'only VWAP rejection' do
      let(:position_data) do
        OpenStruct.new(
          trend_score: 50.0,
          peak_trend_score: 50.0,
          adx: 25.0,
          atr_ratio: 1.0,
          underlying_price: 95.0, # Below VWAP for long
          vwap: 100.0,
          is_long?: true
        )
      end

      it 'triggers ETF' do
        expect(described_class.early_trend_failure?(position_data)).to be true
      end
    end

    context 'all conditions normal' do
      let(:position_data) do
        OpenStruct.new(
          trend_score: 50.0,
          peak_trend_score: 50.0,
          adx: 25.0,
          atr_ratio: 1.0,
          underlying_price: 105.0, # Above VWAP for long
          vwap: 100.0,
          is_long?: true
        )
      end

      it 'does not trigger ETF' do
        expect(described_class.early_trend_failure?(position_data)).to be false
      end
    end
  end
end
