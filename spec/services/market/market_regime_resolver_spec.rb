# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::MarketRegimeResolver do
  describe '.resolve' do
    subject(:regime) { described_class.resolve(candles_15m: candles) }

    context 'when insufficient candles' do
      let(:candles) { generate_candles(base: 22_000, count: 10, trend: :flat) }

      it 'returns :neutral' do
        expect(regime).to eq(:neutral)
      end
    end

    context 'when market is bearish' do
      context 'with lower highs and lower lows sequence' do
        let(:candles) { generate_bearish_candles }

        it 'returns :bearish' do
          expect(regime).to eq(:bearish)
        end
      end

      context 'with close below swing low' do
        let(:candles) { generate_breakdown_candles }

        it 'returns :bearish' do
          expect(regime).to eq(:bearish)
        end
      end

      context 'with gap down and failed reclaim' do
        let(:candles) { generate_gap_down_failed_candles }

        it 'returns :bearish' do
          expect(regime).to eq(:bearish)
        end
      end
    end

    context 'when market is bullish' do
      context 'with higher highs and higher lows sequence' do
        let(:candles) { generate_bullish_candles }

        it 'returns :bullish' do
          expect(regime).to eq(:bullish)
        end
      end

      context 'with close above swing high' do
        let(:candles) { generate_breakout_candles }

        it 'returns :bullish' do
          expect(regime).to eq(:bullish)
        end
      end

      context 'with gap up and held' do
        let(:candles) { generate_gap_up_held_candles }

        it 'returns :bullish' do
          expect(regime).to eq(:bullish)
        end
      end
    end

    context 'when market is neutral' do
      context 'with overlapping highs and lows' do
        let(:candles) { generate_neutral_candles }

        it 'returns :neutral' do
          expect(regime).to eq(:neutral)
        end
      end

      context 'with inside day behavior' do
        let(:candles) { generate_inside_day_candles }

        it 'returns :neutral' do
          expect(regime).to eq(:neutral)
        end
      end

      context 'with mixed signals' do
        let(:candles) { generate_mixed_signal_candles }

        it 'returns :neutral' do
          expect(regime).to eq(:neutral)
        end
      end
    end
  end

  describe '#call' do
    it 'is deterministic with same input' do
      candles = generate_bearish_candles
      results = Array.new(5) { described_class.call(candles_15m: candles) }

      expect(results.uniq.size).to eq(1)
    end
  end

  describe 'candle normalization' do
    context 'with hash candles using symbol keys' do
      let(:candles) do
        generate_candles(base: 22_000, count: 25, trend: :up).map do |c|
          { open: c[:open], high: c[:high], low: c[:low], close: c[:close] }
        end
      end

      it 'processes correctly' do
        expect { described_class.resolve(candles_15m: candles) }.not_to raise_error
      end
    end

    context 'with hash candles using string keys' do
      let(:candles) do
        generate_candles(base: 22_000, count: 25, trend: :up).map do |c|
          { 'open' => c[:open], 'high' => c[:high], 'low' => c[:low], 'close' => c[:close] }
        end
      end

      it 'processes correctly' do
        expect { described_class.resolve(candles_15m: candles) }.not_to raise_error
      end
    end

    context 'with struct candles' do
      let(:candle_struct) { Struct.new(:open, :high, :low, :close, keyword_init: true) }
      let(:candles) do
        generate_candles(base: 22_000, count: 25, trend: :up).map do |c|
          candle_struct.new(open: c[:open], high: c[:high], low: c[:low], close: c[:close])
        end
      end

      it 'processes correctly' do
        expect { described_class.resolve(candles_15m: candles) }.not_to raise_error
      end
    end
  end

  # ---------------------------------------------------------------------------
  # HELPER METHODS FOR GENERATING TEST CANDLE DATA
  # ---------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize

  def generate_candles(base:, count:, trend:, volatility: 20)
    candles = []
    price = base.to_f

    count.times do |_i|
      case trend
      when :up
        price += rand(5..15)
      when :down
        price -= rand(5..15)
      when :flat
        price += rand(-5..5)
      end

      open = price + rand(-volatility..volatility)
      close = price + rand(-volatility..volatility)
      high = [open, close].max + rand(1..volatility)
      low = [open, close].min - rand(1..volatility)

      candles << { open: open, high: high, low: low, close: close }
    end

    candles
  end

  # Generate bearish candles with clear lower highs and lower lows
  def generate_bearish_candles
    candles = []
    price = 22_500.0

    # First 10 candles: establish initial range
    10.times do
      open = price + rand(-10..10)
      close = price + rand(-15..5)
      high = [open, close].max + rand(5..15)
      low = [open, close].min - rand(5..15)
      candles << { open: open, high: high, low: low, close: close }
    end

    # Create clear swing high at index 10 (with SWING_LOOKBACK=3, needs 3 lower on each side)
    # Indices 7,8,9 < 10 > 11,12,13
    first_swing_high = 22_600.0
    candles[7][:high] = first_swing_high - 50
    candles[8][:high] = first_swing_high - 40
    candles[9][:high] = first_swing_high - 30
    candles << { open: first_swing_high - 10, high: first_swing_high, low: first_swing_high - 40,
                 close: first_swing_high - 20 }

    # Candles 11, 12, 13 after swing high
    3.times do |j|
      candles << {
        open: first_swing_high - 50 - (j * 20),
        high: first_swing_high - 30 - (j * 20),
        low: first_swing_high - 70 - (j * 20),
        close: first_swing_high - 60 - (j * 20)
      }
    end

    # Create swing low at index 14
    first_swing_low = 22_400.0
    candles << { open: first_swing_low + 20, high: first_swing_low + 30, low: first_swing_low,
                 close: first_swing_low + 10 }

    # Candles 15, 16, 17 after swing low
    3.times do |j|
      candles << {
        open: first_swing_low + 30 + (j * 10),
        high: first_swing_low + 50 + (j * 10),
        low: first_swing_low + 20 + (j * 10),
        close: first_swing_low + 40 + (j * 10)
      }
    end

    # Create LOWER swing high at index 18
    second_swing_high = 22_550.0 # Lower than first_swing_high
    candles[15][:high] = second_swing_high - 50
    candles[16][:high] = second_swing_high - 40
    candles[17][:high] = second_swing_high - 30
    candles << { open: second_swing_high - 10, high: second_swing_high, low: second_swing_high - 40,
                 close: second_swing_high - 20 }

    # Candles 19, 20, 21 after second swing high
    3.times do |j|
      candles << {
        open: second_swing_high - 50 - (j * 30),
        high: second_swing_high - 30 - (j * 30),
        low: second_swing_high - 80 - (j * 30),
        close: second_swing_high - 70 - (j * 30)
      }
    end

    # Create LOWER swing low at index 22
    second_swing_low = 22_300.0 # Lower than first_swing_low
    candles << { open: second_swing_low + 20, high: second_swing_low + 30, low: second_swing_low,
                 close: second_swing_low + 10 }

    # Final candles with close near second swing low (bearish continuation)
    3.times do |j|
      candles << {
        open: second_swing_low + (j * 5),
        high: second_swing_low + 20 + (j * 5),
        low: second_swing_low - 10 - (j * 5),
        close: second_swing_low + (j * 3)
      }
    end

    candles
  end

  # Generate candles with price breaking below swing low
  def generate_breakdown_candles
    candles = []
    price = 22_400.0

    # Build up with a range
    15.times do |_i|
      open = price + rand(-10..10)
      close = price + rand(-10..10)
      high = [open, close].max + rand(10..25)
      low = [open, close].min - rand(10..25)
      candles << { open: open, high: high, low: low, close: close }
    end

    # Create a clear swing low at index 15 (indices 12,13,14 > 15 < 16,17,18)
    swing_low = 22_300.0
    candles[12][:low] = swing_low + 60
    candles[13][:low] = swing_low + 50
    candles[14][:low] = swing_low + 40
    candles << { open: swing_low + 30, high: swing_low + 50, low: swing_low, close: swing_low + 20 }

    # Candles 16, 17, 18 with higher lows
    3.times do |j|
      candles << {
        open: swing_low + 40 + (j * 10),
        high: swing_low + 80 + (j * 10),
        low: swing_low + 30 + (j * 10),
        close: swing_low + 60 + (j * 10)
      }
    end

    # Then breakdown - close below swing low
    breakdown_close = swing_low - 50
    5.times do |j|
      candles << {
        open: swing_low - (j * 20),
        high: swing_low + 10 - (j * 20),
        low: swing_low - 60 - (j * 20),
        close: breakdown_close - (j * 30)
      }
    end

    candles
  end

  # Generate gap down with failure to reclaim
  def generate_gap_down_failed_candles
    candles = []
    price = 22_500.0

    # Initial candles
    18.times do |_i|
      open = price + rand(-10..10)
      close = price + rand(-10..10)
      high = [open, close].max + rand(10..20)
      low = [open, close].min - rand(10..20)
      candles << { open: open, high: high, low: low, close: close }
    end

    # Gap down: prior candle ends at 22500, next candle opens gap down
    prior_low = 22_450.0
    candles.last[:low] = prior_low
    candles.last[:close] = prior_low + 30

    # Gap candle: high < prior low (gap down)
    gap_high = prior_low - 30 # Creates 30 point gap
    candles << {
      open: gap_high - 20,
      high: gap_high,
      low: gap_high - 60,
      close: gap_high - 40
    }

    # Next 4 candles fail to close above gap midpoint
    4.times do |j|
      base = gap_high - 50 - (j * 10)
      candles << {
        open: base,
        high: base + 20, # Doesn't reach gap_midpoint
        low: base - 20,
        close: base - 5
      }
    end

    candles
  end

  # Generate bullish candles with clear higher highs and higher lows
  def generate_bullish_candles
    candles = []
    price = 22_000.0

    # First 10 candles: establish initial range
    10.times do
      open = price + rand(-10..10)
      close = price + rand(-5..15)
      high = [open, close].max + rand(5..15)
      low = [open, close].min - rand(5..15)
      candles << { open: open, high: high, low: low, close: close }
    end

    # Create swing low at index 10
    first_swing_low = 21_950.0
    candles[7][:low] = first_swing_low + 50
    candles[8][:low] = first_swing_low + 40
    candles[9][:low] = first_swing_low + 30
    candles << { open: first_swing_low + 20, high: first_swing_low + 40, low: first_swing_low,
                 close: first_swing_low + 30 }

    # Candles 11, 12, 13 after swing low
    3.times do |j|
      candles << {
        open: first_swing_low + 50 + (j * 20),
        high: first_swing_low + 80 + (j * 20),
        low: first_swing_low + 40 + (j * 20),
        close: first_swing_low + 70 + (j * 20)
      }
    end

    # Create swing high at index 14
    first_swing_high = 22_100.0
    candles << { open: first_swing_high - 20, high: first_swing_high, low: first_swing_high - 40,
                 close: first_swing_high - 10 }

    # Candles 15, 16, 17 after swing high (pullback)
    3.times do |j|
      candles << {
        open: first_swing_high - 30 - (j * 10),
        high: first_swing_high - 20 - (j * 10),
        low: first_swing_high - 50 - (j * 10),
        close: first_swing_high - 40 - (j * 10)
      }
    end

    # Create HIGHER swing low at index 18
    second_swing_low = 22_000.0 # Higher than first_swing_low
    candles[15][:low] = second_swing_low + 50
    candles[16][:low] = second_swing_low + 40
    candles[17][:low] = second_swing_low + 30
    candles << { open: second_swing_low + 20, high: second_swing_low + 40, low: second_swing_low,
                 close: second_swing_low + 30 }

    # Candles 19, 20, 21 rally
    3.times do |j|
      candles << {
        open: second_swing_low + 60 + (j * 30),
        high: second_swing_low + 100 + (j * 30),
        low: second_swing_low + 50 + (j * 30),
        close: second_swing_low + 90 + (j * 30)
      }
    end

    # Create HIGHER swing high at index 22
    second_swing_high = 22_200.0 # Higher than first_swing_high
    candles << { open: second_swing_high - 20, high: second_swing_high, low: second_swing_high - 40,
                 close: second_swing_high - 10 }

    # Final candles continuing bullish
    3.times do |j|
      candles << {
        open: second_swing_high - 10 + (j * 10),
        high: second_swing_high + 20 + (j * 15),
        low: second_swing_high - 20 + (j * 10),
        close: second_swing_high + 10 + (j * 15)
      }
    end

    candles
  end

  # Generate breakout above swing high
  def generate_breakout_candles
    candles = []
    price = 22_100.0

    # Build up with a range
    15.times do |_i|
      open = price + rand(-10..10)
      close = price + rand(-10..10)
      high = [open, close].max + rand(10..25)
      low = [open, close].min - rand(10..25)
      candles << { open: open, high: high, low: low, close: close }
    end

    # Create a clear swing high at index 15
    swing_high = 22_200.0
    candles[12][:high] = swing_high - 60
    candles[13][:high] = swing_high - 50
    candles[14][:high] = swing_high - 40
    candles << { open: swing_high - 30, high: swing_high, low: swing_high - 50, close: swing_high - 20 }

    # Candles 16, 17, 18 with lower highs (pullback)
    3.times do |j|
      candles << {
        open: swing_high - 40 - (j * 10),
        high: swing_high - 30 - (j * 10),
        low: swing_high - 80 - (j * 10),
        close: swing_high - 50 - (j * 10)
      }
    end

    # Then breakout - close above swing high
    breakout_close = swing_high + 50
    5.times do |j|
      candles << {
        open: swing_high + (j * 20),
        high: swing_high + 60 + (j * 20),
        low: swing_high - 10 + (j * 20),
        close: breakout_close + (j * 30)
      }
    end

    candles
  end

  # Generate gap up that holds
  def generate_gap_up_held_candles
    candles = []
    price = 22_000.0

    # Initial candles
    18.times do |_i|
      open = price + rand(-10..10)
      close = price + rand(-10..10)
      high = [open, close].max + rand(10..20)
      low = [open, close].min - rand(10..20)
      candles << { open: open, high: high, low: low, close: close }
    end

    # Gap up: prior candle high at 22050, next candle opens gap up
    prior_high = 22_050.0
    candles.last[:high] = prior_high
    candles.last[:close] = prior_high - 20

    # Gap candle: low > prior high (gap up)
    gap_low = prior_high + 30 # Creates 30 point gap
    candles << {
      open: gap_low + 20,
      high: gap_low + 60,
      low: gap_low,
      close: gap_low + 40
    }

    # Next 4 candles all close above gap midpoint
    4.times do |j|
      base = gap_low + 30 + (j * 10)
      candles << {
        open: base,
        high: base + 30,
        low: base - 15, # Low can dip but close is above midpoint
        close: base + 20 # Stays above gap_midpoint
      }
    end

    candles
  end

  # Generate neutral/ranging candles with no clear direction
  # Carefully constructed to avoid triggering any bearish or bullish conditions
  def generate_neutral_candles
    candles = []
    base_price = 22_200.0

    # Create a truly flat market:
    # - All candles at the same level (no trends)
    # - Wide overlapping ranges (no clear swings)
    # - Close right at value midpoint (no holding/rejection)
    25.times do |_i|
      # All candles centered at base price
      open = base_price
      close = base_price # Flat closes = no direction
      high = base_price + 30
      low = base_price - 30

      candles << { open: open, high: high, low: low, close: close }
    end

    candles
  end

  # Generate inside day candles (narrow range within prior range)
  # Carefully constructed to be neutral (close at midpoint, no trends)
  def generate_inside_day_candles
    candles = []

    # All candles at same level with overlapping ranges
    # Value midpoint will be (22230 + 22170) / 2 = 22200
    # Close at exactly 22200 to be neutral (not above, not below with rejection)
    25.times do |_i|
      candles << {
        open: 22_200.0,
        high: 22_230.0,
        low: 22_170.0,
        close: 22_200.0 # Exactly at midpoint = neutral
      }
    end

    candles
  end

  # Generate candles with mixed bullish and bearish signals
  # Truly choppy market with no clear swing structure
  def generate_mixed_signal_candles
    candles = []

    # Create perfectly flat market:
    # - All highs/lows identical (no swings)
    # - Close exactly at value midpoint (not above, not below with rejection)
    # - No gaps
    # Value midpoint = (22230 + 22170) / 2 = 22200
    25.times do |_i|
      candles << {
        open: 22_200.0,
        high: 22_230.0,
        low: 22_170.0,
        close: 22_200.0 # Exactly at midpoint = neutral
      }
    end

    candles
  end
  # rubocop:enable Metrics/AbcSize
end
