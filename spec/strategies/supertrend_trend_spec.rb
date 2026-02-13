# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SupertrendTrend do
  describe '.direction' do
    # Trend at i: close >= line[i] ? :bullish : :bearish
    # flip_up = prev :bearish, current :bullish => :long
    # flip_down = prev :bullish, current :bearish => :short
    # else => :none

    context 'when series has closes and supertrend line aligned by index' do
      it 'returns :long on flip_up (bearish to bullish)' do
        # prev: close < line => bearish; current: close >= line => bullish
        closes = [100.0, 98.0, 102.0] # last two: 98 < 105 bearish, 102 >= 101 bullish
        line = [99.0, 105.0, 101.0]
        series = double('series', closes: closes)
        result = described_class.direction(series: series, supertrend_result: { line: line })
        expect(result).to eq(:long)
      end

      it 'returns :short on flip_down (bullish to bearish)' do
        # prev: close >= line => bullish; current: close < line => bearish
        closes = [100.0, 105.0, 97.0] # last two: 105 >= 104 bullish, 97 < 100 bearish
        line = [99.0, 104.0, 100.0]
        series = double('series', closes: closes)
        result = described_class.direction(series: series, supertrend_result: { line: line })
        expect(result).to eq(:short)
      end

      it 'returns :none when no flip (both bars same trend)' do
        # both bullish: close >= line
        closes = [100.0, 102.0, 104.0]
        line = [99.0, 101.0, 103.0]
        series = double('series', closes: closes)
        result = described_class.direction(series: series, supertrend_result: { line: line })
        expect(result).to eq(:none)
      end

      it 'returns :none when both bars bearish' do
        closes = [100.0, 98.0, 96.0]
        line = [101.0, 99.0, 97.0] # close < line at each
        series = double('series', closes: closes)
        result = described_class.direction(series: series, supertrend_result: { line: line })
        expect(result).to eq(:none)
      end
    end

    context 'when series exposes closes via candles' do
      it 'returns :long when flip_up from candles' do
        candles = [
          double('c', close: 100.0),
          double('c', close: 98.0),
          double('c', close: 102.0)
        ]
        line = [99.0, 105.0, 101.0]
        series = double('series', closes: nil, candles: candles)
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

      it 'returns :none when only one valid bar (last_index < 1)' do
        closes = [100.0]
        line = [99.0]
        series = double('series', closes: closes)
        result = described_class.direction(series: series, supertrend_result: { line: line })
        expect(result).to eq(:none)
      end

      it 'returns :none when closes length != line length' do
        series = double('series', closes: [1, 2])
        result = described_class.direction(series: series, supertrend_result: { line: [1, 2, 3] })
        expect(result).to eq(:none)
      end
    end
  end
end
