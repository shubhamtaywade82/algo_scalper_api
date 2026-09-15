# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdaptiveSupertrendKnnStrategy do
  subject { described_class.new(series: series, k_neighbors: 3, min_confidence: 50.0) }

  let(:candles) do
    (1..35).map do |i|
      double(
        'Candle',
        open: 100.0 + i,
        high: 102.0 + i,
        low: 99.0 + i,
        close: 101.0 + i,
        timestamp: Time.current - (35 - i).minutes
      )
    end
  end

  let(:series) { double('CandleSeries', candles: candles, rsi: 65.0, adx: 25.0, atr: 1.5) }

  describe '#generate_signal' do
    it 'returns nil when candles size is less than 30' do
      short_series = double('CandleSeries', candles: candles.first(10))
      strat = described_class.new(series: short_series)
      expect(strat.generate_signal).to be_nil
    end

    it 'returns a signal hash when conditions are met' do
      signal = subject.generate_signal
      expect(signal).to be_a(Hash)
      expect(signal[:action]).to be_in(%i[buy_call buy_put])
      expect(signal[:confidence]).to be >= 50.0
      expect(signal[:direction]).to be_in(%i[bullish bearish])
    end
  end
end
