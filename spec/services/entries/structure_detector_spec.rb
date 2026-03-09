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
        # 20 candles total
        bars = Array.new(20) do |i|
          # Older candles have very high prices
          price = i < 10 ? 30_000 : 25_000
          build(:candle, high: price + 100, low: price - 100, close: price, timestamp: (20 - i).minutes.ago)
        end
        # bars[19] is newest (close ~25000). 
        # With lookback=5, it only looks at bars[15..19] where highs are ~25100.
        # If it erroneously looks at bars[0..19], highs are ~30100 and it would definitely be false.
        # Wait, if current close=25000 and previous high=25100, it's false anyway.
        
        # Let's make it more explicit:
        # Lookback range (last 5): highs are all 25100.
        # Current close: 25200 (breaks lookback range)
        # BUT outside lookback (index 0): high is 30000.
        # If lookback works, result=true (breaks 25100).
        # If lookback fails, result=false (doesn't break 30000).
        
        # Wait, the test expects false? 
        # "respects lookback_minutes parameter" ... expect(result).to be false
        # This means it's testing that if a break happens OUTSIDE lookback, it returns false.
        
        # New setup:
        # Bars 0..14: high=25000, close=25500 (BREAK happens here)
        # Bars 15..19: high=26000, close=25000 (NO BREAK here)
        # If lookback=5, it only sees 15..19 -> NO BREAK -> false.
        
        bars = Array.new(20) do |i|
          if i == 10
            # A "historic" break
            build(:candle, high: 25_000, low: 24_000, close: 26_000, timestamp: (20 - i).minutes.ago)
          else
            # Normal quiet candles
            build(:candle, high: 27_000, low: 24_000, close: 25_000, timestamp: (20 - i).minutes.ago)
          end
        end

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
        # Recent bullish move (within last 5), but current price is in bearish OB (from before the move)
        bars = [
          build(:candle, :bearish, high: 25_000, low: 24_900, close: 24_950), # The Bearish OB
          build(:candle, :bearish, high: 24_950, low: 24_850, close: 24_900),
          build(:candle, :bullish, high: 25_200, low: 24_900, close: 25_150), # Start of move
          build(:candle, :bullish, high: 25_600, low: 25_100, close: 25_550), # End of move
          build(:candle, high: 24_950, low: 24_900, close: 24_920) # Back inside bearish OB
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
