# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SupertrendTrend do
  describe '.direction' do
    # Uses last bar only: close >= line[last] => :long, else :short.

    context 'when series has closes and supertrend line aligned by index' do
      it 'returns :long when last close is at or above supertrend line' do
        closes = [100.0, 98.0, 102.0]
        line = [99.0, 105.0, 101.0]
        series = double('series', closes: closes)
        result = described_class.direction(series: series, supertrend_result: { line: line })
        expect(result).to eq(:long)
      end

      it 'returns :short when last close is below supertrend line' do
        closes = [100.0, 105.0, 97.0]
        line = [99.0, 104.0, 100.0]
        series = double('series', closes: closes)
        result = described_class.direction(series: series, supertrend_result: { line: line })
        expect(result).to eq(:short)
      end

      it 'returns :long when last bar is bullish vs line' do
        closes = [100.0, 102.0, 104.0]
        line = [99.0, 101.0, 103.0]
        series = double('series', closes: closes)
        result = described_class.direction(series: series, supertrend_result: { line: line })
        expect(result).to eq(:long)
      end

      it 'returns :short when last bar is bearish vs line' do
        closes = [100.0, 98.0, 96.0]
        line = [101.0, 99.0, 97.0]
        series = double('series', closes: closes)
        result = described_class.direction(series: series, supertrend_result: { line: line })
        expect(result).to eq(:short)
      end
    end

    context 'when series exposes closes via candles' do
      it 'returns :long when last close is above line from candles' do
        candles = [
          double('c', close: 100.0),
          double('c', close: 98.0),
          double('c', close: 102.0)
        ]
        line = [99.0, 105.0, 101.0]
        series = Struct.new(:candles).new(candles)
        result = described_class.direction(series: series, supertrend_result: { line: line })
        expect(result).to eq(:long)
      end
    end

    context 'when inputs are invalid or insufficient' do
      it 'returns :none when series is nil' do
        result = described_class.direction(series: nil, supertrend_result: { line: [1, 2, 3] })
        expect(result).to eq(:none)
      end

      it 'returns :none when supertrend_result is nil' do
        series = double('series', closes: [1, 2, 3])
        result = described_class.direction(series: series, supertrend_result: nil)
        expect(result).to eq(:none)
      end

      it 'returns :none when line is empty' do
        series = double('series', closes: [1, 2, 3])
        result = described_class.direction(series: series, supertrend_result: { line: [] })
        expect(result).to eq(:none)
      end

      it 'returns :long when only one bar and close is above line' do
        closes = [100.0]
        line = [99.0]
        series = double('series', closes: closes)
        result = described_class.direction(series: series, supertrend_result: { line: line })
        expect(result).to eq(:long)
      end

      it 'returns :none when closes length != line length' do
        series = double('series', closes: [1, 2])
        result = described_class.direction(series: series, supertrend_result: { line: [1, 2, 3] })
        expect(result).to eq(:none)
      end
    end
  end
end
