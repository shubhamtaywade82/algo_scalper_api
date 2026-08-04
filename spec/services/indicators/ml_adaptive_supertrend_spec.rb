# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::MlAdaptiveSupertrend do
  let(:symbol) { 'NIFTY' }
  let(:interval) { '5' }
  let(:series) { CandleSeries.new(symbol: symbol, interval: interval) }
  let(:config) { { atr_len: 10, factor: 1.0, training_period: 100 } }
  let(:service) { described_class.new(series: series, config: config) }

  def add_candles(count, start_price: 20_000.0, volatility: 10.0, trend: 0.0)
    current_price = start_price
    count.times do |_i|
      # Add some randomness but follow the trend
      movement = ((rand - 0.5) * volatility) + trend
      open = current_price
      close = open + movement
      high = [open, close].max + (rand * volatility * 0.5)
      low = [open, close].min - (rand * volatility * 0.5)

      candle = Candle.new(
        timestamp: Time.zone.parse('2024-01-01 10:00:00 IST') + series.candles.size.minutes,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: 1000
      )
      series.add_candle(candle)
      current_price = close
    end
  end

  describe '#call' do
    context 'with insufficient data' do
      it 'returns empty results if no candles' do
        result = service.call
        expect(result[:super_trend]).to be_empty
      end

      it 'returns nil direction for early candles' do
        add_candles(5)
        result = service.call
        expect(result[:direction].first).to be_nil
      end
    end

    context 'with sufficient data' do
      before do
        # Add 150 candles to satisfy training_period (100) + atr_len (10)
        add_candles(150, start_price: 20_000.0, volatility: 20.0, trend: 5.0)
      end

      it 'calculates super_trend for later candles' do
        result = service.call
        last_index = result[:last_index]
        expect(result[:super_trend][last_index]).not_to be_nil
        expect(result[:direction][last_index]).not_to be_nil
        expect(result[:regimes][last_index]).not_to be_nil
      end

      it 'detects bullish trend when price is rising' do
        # Add clearly bullish candles
        add_candles(20, start_price: series.candles.last.close, volatility: 5.0, trend: 50.0)
        result = service.call
        expect(result[:direction].last).to eq(-1) # -1 is Bullish in this implementation
      end

      it 'detects bearish trend when price is falling' do
        # Add clearly bearish candles
        add_candles(20, start_price: series.candles.last.close, volatility: 5.0, trend: -50.0)
        result = service.call
        expect(result[:direction].last).to eq(1) # 1 is Bearish
      end

      it 'transitions from bullish to bearish' do
        # 1. Bullish phase
        add_candles(20, start_price: 20_000.0, volatility: 5.0, trend: 100.0)
        # 2. Bearish crash
        add_candles(5, start_price: series.candles.last.close, volatility: 5.0, trend: -300.0)

        result = service.call
        # Check that we have at least one bearish signal at the end
        expect(result[:direction].last(5)).to include(1)
      end
    end

    context 'volatility regimes' do
      it 'detects different regimes' do
        # 1. Low vol period
        add_candles(110, volatility: 2.0)
        # 2. High vol spike
        add_candles(10, volatility: 100.0)

        result = service.call
        regimes = result[:regimes].compact
        expect(regimes.uniq.size).to be > 1
        # The last few should be high volatility (regime 0)
        expect(result[:regimes].last).to eq(0)
      end
    end
  end
end

RSpec.describe Indicators::MlAdaptiveSupertrendIndicator do
  let(:symbol) { 'NIFTY' }
  let(:interval) { '5' }
  let(:series) { CandleSeries.new(symbol: symbol, interval: interval) }
  let(:config) { { atr_len: 10, factor: 1.0, training_period: 100 } }
  let(:indicator) { described_class.new(series: series, config: config) }

  before do
    # Add enough candles
    120.times do |i|
      candle = Candle.new(
        timestamp: Time.zone.parse('2024-01-01 10:00:00 IST') + i.minutes,
        open: 20_000, high: 20_010, low: 19_990, close: 20_005, volume: 100
      )
      series.add_candle(candle)
    end
  end

  describe '#calculate_at' do
    it 'returns a valid result hash' do
      result = indicator.calculate_at(115)
      expect(result).to be_a(Hash)
      expect(result[:direction]).to be_in(%i[bullish bearish])
      expect(result[:regime]).to be_in(%i[high_volatility medium_volatility low_volatility])
      expect(result[:value]).to be_a(Numeric)
    end

    it 'caches the service result' do
      expect(Indicators::MlAdaptiveSupertrend).to receive(:new).once.and_call_original
      indicator.calculate_at(110)
      indicator.calculate_at(111)
    end

    it 'respects trading hours if filter enabled' do
      indicator_with_filter = described_class.new(series: series, config: config.merge(trading_hours_filter: true))

      # Forge a candle outside trading hours (9:00 AM IST)
      candle = Candle.new(
        timestamp: Time.zone.parse('2024-01-01 09:00:00 IST'),
        open: 20_000, high: 20_010, low: 19_990, close: 20_005, volume: 100
      )
      series.add_candle(candle)
      idx = series.candles.size - 1

      expect(indicator_with_filter.calculate_at(idx)).to be_nil
    end
  end
end
