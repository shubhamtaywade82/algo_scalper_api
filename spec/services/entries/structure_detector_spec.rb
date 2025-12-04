# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::StructureDetector do
  describe '.bos?' do
    context 'with valid data' do
      it 'detects bullish BOS when price breaks above previous swing high' do
        bars = [
          build(:candle, high: 25_000, low: 24_900, close: 24_950),
          build(:candle, high: 25_100, low: 24_950, close: 25_050),
          build(:candle, high: 25_200, low: 25_000, close: 25_150) # Breaks above 25_100
        ]

        result = described_class.bos?(bars, lookback_minutes: 10)

        expect(result).to be true
      end

      it 'detects bearish BOS when price breaks below previous swing low' do
        bars = [
          build(:candle, high: 25_100, low: 24_900, close: 25_000),
          build(:candle, high: 25_050, low: 24_800, close: 24_950),
          build(:candle, high: 24_900, low: 24_700, close: 24_750) # Breaks below 24_800
        ]

        result = described_class.bos?(bars, lookback_minutes: 10)

        expect(result).to be true
      end

      it 'returns false when no BOS detected' do
        bars = [
          build(:candle, high: 25_000, low: 24_900, close: 24_950),
          build(:candle, high: 25_050, low: 24_950, close: 25_000),
          build(:candle, high: 25_100, low: 25_000, close: 25_050) # No break
        ]

        result = described_class.bos?(bars, lookback_minutes: 10)

        expect(result).to be false
      end

      it 'respects lookback_minutes parameter' do
        bars = Array.new(20) do |i|
          build(:candle, high: 25_000 + i, low: 24_900 + i, close: 24_950 + i, timestamp: i.minutes.ago)
        end
        bars.last.close = 26_000 # Breaks high, but outside lookback

        result = described_class.bos?(bars, lookback_minutes: 5)

        expect(result).to be false
      end
    end

    context 'with invalid data' do
      it 'returns false when bars is nil' do
        result = described_class.bos?(nil)

        expect(result).to be false
      end

      it 'returns false when bars is empty' do
        result = described_class.bos?([])

        expect(result).to be false
      end

      it 'returns false when bars has less than 3 candles' do
        bars = [
          build(:candle),
          build(:candle)
        ]

        result = described_class.bos?(bars)

        expect(result).to be false
      end
    end
  end

  describe '.inside_opposite_ob?' do
    context 'with valid data' do
      it 'detects when price is inside opposite Order Block' do
        # Recent bullish move, but price is in bearish OB
        bars = [
          build(:candle, :bearish, high: 25_000, low: 24_900, close: 24_950),
          build(:candle, :bullish, high: 25_200, low: 25_000, close: 25_150),
          build(:candle, :bullish, high: 25_300, low: 25_100, close: 25_250),
          build(:candle, high: 24_950, low: 24_900, close: 24_920) # Inside bearish OB
        ]

        result = described_class.inside_opposite_ob?(bars)

        expect(result).to be true
      end

      it 'returns false when not inside opposite OB' do
        bars = [
          build(:candle, :bullish, high: 25_000, low: 24_900, close: 24_950),
          build(:candle, :bullish, high: 25_200, low: 25_000, close: 25_150),
          build(:candle, high: 25_300, low: 25_200, close: 25_250) # Outside OB
        ]

        result = described_class.inside_opposite_ob?(bars)

        expect(result).to be false
      end
    end

    context 'with invalid data' do
      it 'returns false when bars has less than 3 candles' do
        bars = [
          build(:candle),
          build(:candle)
        ]

        result = described_class.inside_opposite_ob?(bars)

        expect(result).to be false
      end
    end
  end

  describe '.inside_fvg?' do
    context 'with valid data' do
      it 'detects when price is inside opposing Fair Value Gap' do
        # Creates bullish FVG, but price is in bearish FVG
        bars = [
          build(:candle, high: 25_000, low: 24_900, close: 24_950),
          build(:candle, high: 25_200, low: 25_100, close: 25_150), # Gap up
          build(:candle, high: 25_300, low: 25_200, close: 25_250),
          build(:candle, high: 24_950, low: 24_850, close: 24_900) # Inside FVG
        ]

        result = described_class.inside_fvg?(bars)

        expect(result).to be true
      end

      it 'returns false when not inside opposing FVG' do
        bars = [
          build(:candle, high: 25_000, low: 24_900, close: 24_950),
          build(:candle, high: 25_200, low: 25_100, close: 25_150),
          build(:candle, high: 25_300, low: 25_200, close: 25_250),
          build(:candle, high: 25_400, low: 25_300, close: 25_350) # Outside FVG
        ]

        result = described_class.inside_fvg?(bars)

        expect(result).to be false
      end
    end

    context 'with invalid data' do
      it 'returns false when bars has less than 3 candles' do
        bars = [
          build(:candle),
          build(:candle)
        ]

        result = described_class.inside_fvg?(bars)

        expect(result).to be false
      end
    end
  end
end
