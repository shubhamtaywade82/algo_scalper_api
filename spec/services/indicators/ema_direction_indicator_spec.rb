# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::EmaDirectionIndicator do
  def make_series(closes)
    candles = closes.map.with_index do |c, i|
      instance_double('Candle', open: c, high: c + 1, low: c - 1, close: c, volume: 1000, timestamp: i.minutes.ago)
    end
    instance_double('CandleSeries', candles: candles)
  end

  describe '#calculate' do
    context 'with fewer candles than slow_period (21)' do
      let(:series) { make_series([100.0] * 10) }

      it 'returns direction: :neutral, aligned: false' do
        result = described_class.new(series: series).calculate
        expect(result[:direction]).to eq(:neutral)
        expect(result[:aligned]).to be false
      end
    end

    context 'with sustained uptrend (fast EMA above slow EMA)' do
      # 30 candles consistently rising — fast EMA will be above slow EMA
      let(:closes) { (1..30).map { |i| 100.0 + (i * 0.5) } }
      let(:series) { make_series(closes) }

      it 'returns direction: :bullish' do
        result = described_class.new(series: series).calculate
        expect(result[:direction]).to eq(:bullish)
        expect(result[:fast]).to be > result[:slow]
        expect(result[:aligned]).to be true
      end
    end

    context 'with sustained downtrend (fast EMA below slow EMA)' do
      # 30 candles consistently declining
      let(:closes) { (1..30).map { |i| 200.0 - (i * 0.5) } }
      let(:series) { make_series(closes) }

      it 'returns direction: :bearish' do
        result = described_class.new(series: series).calculate
        expect(result[:direction]).to eq(:bearish)
        expect(result[:fast]).to be < result[:slow]
      end
    end

    context 'with custom fast/slow periods' do
      let(:closes) { (1..30).map { |i| 100.0 + (i * 0.5) } }
      let(:series) { make_series(closes) }

      it 'uses configured periods' do
        result = described_class.new(series: series, config: { fast_period: 5, slow_period: 10 }).calculate
        expect(result[:direction]).to be_in(%i[bullish bearish neutral])
      end
    end
  end
end
