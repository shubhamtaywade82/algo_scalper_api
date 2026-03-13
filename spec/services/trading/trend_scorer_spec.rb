# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::TrendScorer do
  let(:symbol) { 'NIFTY' }
  let(:series_5m) { CandleSeries.new(symbol: symbol, interval: '5') }
  let(:series_15m) { CandleSeries.new(symbol: symbol, interval: '15') }
  let(:scorer) { described_class.new(series_5m: series_5m, series_15m: series_15m) }

  def add_candles(series, count, start_price, trend_type = :flat)
    count.times do |i|
      price = case trend_type
              when :bullish then start_price + i
              when :bearish then start_price - i
              else start_price
              end

      series.add_candle(
        Candle.new(
          timestamp: Time.current - (count - i).minutes,
          open: price, high: price + 0.5, low: price - 0.5, close: price, volume: 1000
        )
      )
    end
  end

  describe '#call' do
    context 'with insufficient data' do
      it 'returns zero score' do
        add_candles(series_5m, 10, 100)
        expect(scorer.call[:score]).to eq(0)
      end
    end

    context 'in a clear bullish trend' do
      before do
        # Create a HH/HL pattern manually or via helper
        # We need at least 20 candles for the scorer to work
        # And we need clear swing points for Market Structure

        # Start padding
        5.times { |i| series_5m.add_candle(Candle.new(timestamp: Time.current - (60 - i).minutes, open: 100, high: 100.1, low: 99.9, close: 100, volume: 1000)) }
        # Bullish Swing 1
        10.times { |i| series_5m.add_candle(Candle.new(timestamp: Time.current - (50 - i).minutes, open: 100 + i, high: 100 + i + 1, low: 100 + i - 1, close: 100 + i, volume: 1000)) }
        # Pullback 1 (Higher Low)
        5.times { |i| series_5m.add_candle(Candle.new(timestamp: Time.current - (40 - i).minutes, open: 110 - i, high: 110 - i + 1, low: 110 - i - 1, close: 110 - i, volume: 1000)) }
        # Bullish Swing 2 (Higher High)
        10.times { |i| series_5m.add_candle(Candle.new(timestamp: Time.current - (30 - i).minutes, open: 105 + i, high: 105 + i + 1, low: 105 + i - 1, close: 105 + i, volume: 1000)) }
        # Padding to confirm last swing (must be lower than peak)
        5.times { |i| series_5m.add_candle(Candle.new(timestamp: Time.current - (5 - i).minutes, open: 114, high: 114.1, low: 113.8, close: 113.9, volume: 1000)) }

        # Setup 15m as bullish
        15.times { |i| series_15m.add_candle(Candle.new(timestamp: Time.current - (400 - (i * 15)).minutes, open: 100 + i, high: 100 + i + 1, low: 100 + i - 1, close: 100 + i, volume: 1000)) }

        # Mock ADX to avoid insufficient data issues
        # Mock Supertrend to bullish
        allow(series_5m).to receive_messages(adx: 30, supertrend_signal: :bullish)
      end

      it 'returns a high bullish score' do
        result = scorer.call
        expect(result[:score]).to be > 60
        expect(result[:bias]).to eq(:bullish)
      end
    end

    context 'in a clear bearish trend' do
      before do
        # Start padding
        5.times { |i| series_5m.add_candle(Candle.new(timestamp: Time.current - (60 - i).minutes, open: 100, high: 100.1, low: 99.9, close: 100, volume: 1000)) }
        # Bearish Swings
        10.times { |i| series_5m.add_candle(Candle.new(timestamp: Time.current - (50 - i).minutes, open: 100 - i, high: 100 - i + 1, low: 100 - i - 1, close: 100 - i, volume: 1000)) }
        5.times { |i| series_5m.add_candle(Candle.new(timestamp: Time.current - (40 - i).minutes, open: 90 + i, high: 90 + i + 1, low: 90 + i - 1, close: 90 + i, volume: 1000)) }
        10.times { |i| series_5m.add_candle(Candle.new(timestamp: Time.current - (30 - i).minutes, open: 95 - i, high: 95 - i + 1, low: 95 - i - 1, close: 95 - i, volume: 1000)) }
        # Padding to confirm last swing (must be higher than previous low)
        5.times { |i| series_5m.add_candle(Candle.new(timestamp: Time.current - (5 - i).minutes, open: 86, high: 86.2, low: 85.8, close: 85.9, volume: 1000)) }

        # Setup 15m as bearish
        15.times { |i| series_15m.add_candle(Candle.new(timestamp: Time.current - (400 - (i * 15)).minutes, open: 100 - i, high: 100 - i + 1, low: 100 - i - 1, close: 100 - i, volume: 1000)) }

        allow(series_5m).to receive_messages(adx: 35, supertrend_signal: :bearish)
      end

      it 'returns a high bearish score' do
        result = scorer.call
        expect(result[:score]).to be > 60
        expect(result[:bias]).to eq(:bearish)
      end
    end

    context 'in a weak trend (ADX filter)' do
      before do
        # Trending candles but low ADX
        30.times { |i| series_5m.add_candle(Candle.new(timestamp: Time.current - (50 - i).minutes, open: 100 + i, high: 100 + i + 1, low: 100 + i - 1, close: 100 + i, volume: 1000)) }
        allow(series_5m).to receive(:adx).and_return(15)
      end

      it 'reduces the score by 50%' do
        # We need to calculate what the score would be without the filter
        # It's hard to predict exactly due to structural detection, so we'll just check if it's halved
        scorer_high_adx = described_class.new(series_5m: series_5m)
        allow(series_5m).to receive(:adx).and_return(30)
        score1 = scorer_high_adx.call[:score]

        allow(series_5m).to receive(:adx).and_return(15)
        score2 = scorer.call[:score]

        expect(score2).to eq(score1 * 0.5)
      end
    end
  end
end
