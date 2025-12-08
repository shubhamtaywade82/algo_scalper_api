# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::BaseIndicator do
  let(:series) { CandleSeries.new(symbol: 'NIFTY', interval: '5') }
  let(:config) { {} }

  # Create a concrete implementation for testing
  class TestIndicator < Indicators::BaseIndicator
    def min_required_candles
      10
    end

    def ready?(index)
      index >= min_required_candles
    end

    def calculate_at(index)
      return nil unless ready?(index)
      return nil unless trading_hours?(series.candles[index])

      {
        value: 100.0,
        direction: :bullish,
        confidence: 75
      }
    end
  end

  describe '#initialize' do
    it 'initializes with series and config' do
      indicator = TestIndicator.new(series: series, config: config)
      expect(indicator.series).to eq(series)
      expect(indicator.config).to eq(config)
    end
  end

  describe '#name' do
    it 'returns snake_case name from class name' do
      indicator = TestIndicator.new(series: series, config: config)
      expect(indicator.name).to eq('test_indicator')
    end

    it 'handles namespaced classes' do
      class Indicators::TestNamespacedIndicator < Indicators::BaseIndicator
        def min_required_candles; 10; end
        def ready?(index); index >= 10; end
        def calculate_at(index); nil; end
      end

      indicator = Indicators::TestNamespacedIndicator.new(series: series, config: config)
      expect(indicator.name).to eq('test_namespaced_indicator')
    end
  end

  describe '#trading_hours?' do
    let(:indicator) { TestIndicator.new(series: series, config: config) }

    context 'when trading_hours_filter is enabled' do
      let(:config) { { trading_hours_filter: true } }

      it 'returns true for candles within trading hours' do
        candle = Candle.new(
          ts: Time.zone.parse('2024-01-01 10:30:00 IST'),
          open: 22000,
          high: 22050,
          low: 21980,
          close: 22020,
          volume: 1000
        )
        expect(indicator.trading_hours?(candle)).to be true
      end

      it 'returns false for candles outside trading hours' do
        candle = Candle.new(
          ts: Time.zone.parse('2024-01-01 09:00:00 IST'),
          open: 22000,
          high: 22050,
          low: 21980,
          close: 22020,
          volume: 1000
        )
        expect(indicator.trading_hours?(candle)).to be false
      end
    end

    context 'when trading_hours_filter is disabled' do
      let(:config) { { trading_hours_filter: false } }

      it 'returns true for all candles' do
        candle = Candle.new(
          ts: Time.zone.parse('2024-01-01 09:00:00 IST'),
          open: 22000,
          high: 22050,
          low: 21980,
          close: 22020,
          volume: 1000
        )
        expect(indicator.trading_hours?(candle)).to be true
      end
    end
  end

  describe 'abstract methods' do
    it 'raises NotImplementedError for calculate_at' do
      expect do
        Indicators::BaseIndicator.new(series: series, config: config).calculate_at(0)
      end.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for ready?' do
      expect do
        Indicators::BaseIndicator.new(series: series, config: config).ready?(0)
      end.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for min_required_candles' do
      expect do
        Indicators::BaseIndicator.new(series: series, config: config).min_required_candles
      end.to raise_error(NotImplementedError)
    end
  end
end
