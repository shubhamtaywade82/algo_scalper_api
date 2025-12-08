# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::IndicatorFactory do
  let(:series) { CandleSeries.new(symbol: 'NIFTY', interval: '5') }

  describe '.build_indicator' do
    context 'with supertrend indicator' do
      it 'creates SupertrendIndicator instance' do
        config = {
          type: 'supertrend',
          config: { period: 7, multiplier: 3.0 }
        }
        indicator = described_class.build_indicator(series: series, config: config)
        expect(indicator).to be_a(Indicators::SupertrendIndicator)
      end

      it 'accepts st as alias' do
        config = {
          type: 'st',
          config: { period: 7, multiplier: 3.0 }
        }
        indicator = described_class.build_indicator(series: series, config: config)
        expect(indicator).to be_a(Indicators::SupertrendIndicator)
      end
    end

    context 'with adx indicator' do
      it 'creates AdxIndicator instance' do
        config = {
          type: 'adx',
          config: { period: 14, min_strength: 20 }
        }
        indicator = described_class.build_indicator(series: series, config: config)
        expect(indicator).to be_a(Indicators::AdxIndicator)
      end
    end

    context 'with rsi indicator' do
      it 'creates RsiIndicator instance' do
        config = {
          type: 'rsi',
          config: { period: 14 }
        }
        indicator = described_class.build_indicator(series: series, config: config)
        expect(indicator).to be_a(Indicators::RsiIndicator)
      end
    end

    context 'with macd indicator' do
      it 'creates MacdIndicator instance' do
        config = {
          type: 'macd',
          config: { fast_period: 12, slow_period: 26, signal_period: 9 }
        }
        indicator = described_class.build_indicator(series: series, config: config)
        expect(indicator).to be_a(Indicators::MacdIndicator)
      end
    end

    context 'with trend_duration indicator' do
      it 'creates TrendDurationIndicator instance' do
        config = {
          type: 'trend_duration',
          config: { hma_length: 20, trend_length: 5 }
        }
        indicator = described_class.build_indicator(series: series, config: config)
        expect(indicator).to be_a(Indicators::TrendDurationIndicator)
      end

      it 'accepts trend_duration_forecast as alias' do
        config = {
          type: 'trend_duration_forecast',
          config: { hma_length: 20 }
        }
        indicator = described_class.build_indicator(series: series, config: config)
        expect(indicator).to be_a(Indicators::TrendDurationIndicator)
      end

      it 'accepts tdf as alias' do
        config = {
          type: 'tdf',
          config: { hma_length: 20 }
        }
        indicator = described_class.build_indicator(series: series, config: config)
        expect(indicator).to be_a(Indicators::TrendDurationIndicator)
      end
    end

    context 'with unknown indicator type' do
      it 'returns nil and logs warning' do
        config = {
          type: 'unknown_indicator',
          config: {}
        }
        expect(Rails.logger).to receive(:warn).with(match(/Unknown indicator type/))
        indicator = described_class.build_indicator(series: series, config: config)
        expect(indicator).to be_nil
      end
    end

    context 'with error during creation' do
      it 'handles errors gracefully' do
        config = {
          type: 'supertrend',
          config: { period: 7, multiplier: 3.0 }
        }
        allow(Indicators::SupertrendIndicator).to receive(:new).and_raise(StandardError, 'Test error')
        expect(Rails.logger).to receive(:error).with(match(/Error building indicator/))
        indicator = described_class.build_indicator(series: series, config: config)
        expect(indicator).to be_nil
      end
    end

    context 'with global config merging' do
      it 'merges global config with indicator config' do
        config = {
          type: 'adx',
          config: { period: 14 }
        }
        global_config = { min_strength: 20, trading_hours_filter: true }
        indicator = described_class.build_indicator(series: series, config: config, global_config: global_config)
        expect(indicator).to be_a(Indicators::AdxIndicator)
        expect(indicator.config[:min_strength]).to eq(20)
        expect(indicator.config[:trading_hours_filter]).to be true
      end
    end
  end

  describe '.build_indicators' do
    it 'builds multiple indicators from config array' do
      config = {
        indicators: [
          { type: 'supertrend', config: { period: 7 } },
          { type: 'adx', config: { period: 14 } }
        ]
      }
      indicators = described_class.build_indicators(series: series, config: config)
      expect(indicators.size).to eq(2)
      expect(indicators[0]).to be_a(Indicators::SupertrendIndicator)
      expect(indicators[1]).to be_a(Indicators::AdxIndicator)
    end

    it 'filters out nil indicators' do
      config = {
        indicators: [
          { type: 'supertrend', config: { period: 7 } },
          { type: 'unknown', config: {} }
        ]
      }
      indicators = described_class.build_indicators(series: series, config: config)
      expect(indicators.size).to eq(1)
      expect(indicators[0]).to be_a(Indicators::SupertrendIndicator)
    end

    it 'returns empty array when no indicators configured' do
      config = { indicators: [] }
      indicators = described_class.build_indicators(series: series, config: config)
      expect(indicators).to eq([])
    end

    it 'returns empty array when indicators key missing' do
      config = {}
      indicators = described_class.build_indicators(series: series, config: config)
      expect(indicators).to eq([])
    end
  end
end
