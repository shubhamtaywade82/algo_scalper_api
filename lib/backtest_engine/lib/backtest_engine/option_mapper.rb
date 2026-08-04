module BacktestEngine
  class OptionMapper
    STRIKE_STEP = 50

    # option_data structure:
    # {
    #   call: { 23500 => [ { timestamp:, open:, high:, low:, close:, iv:, oi:, spot: }, ... ], ... },
    #   put:  { 23500 => [ { timestamp:, ... }, ... ], ... }
    # }
    def initialize(option_data)
      @option_data = option_data
    end

    def atm_strike(spot)
      return nil unless spot

      (spot.to_f / STRIKE_STEP).round * STRIKE_STEP
    end

    def select_strike(spot, bias, offset_mode: :atm)
      base_strike = atm_strike(spot)
      return nil unless base_strike

      strike = apply_offset(base_strike, offset_mode)

      case bias
      when :bullish
        { type: :call, strike: strike }
      when :bearish
        { type: :put, strike: strike }
      else
        nil
      end
    end

    def price_at(timestamp, strike, type)
      candles = candles_for(strike, type)
      return nil unless candles

      candles.find { |candle| candle[:timestamp] == timestamp }
    end

    private

    def apply_offset(base_strike, offset_mode)
      case offset_mode
      when :atm
        base_strike
      when :atm_plus_1
        base_strike + STRIKE_STEP
      when :atm_minus_1
        base_strike - STRIKE_STEP
      when :atm_plus_2
        base_strike + (2 * STRIKE_STEP)
      when :atm_minus_2
        base_strike - (2 * STRIKE_STEP)
      else
        base_strike
      end
    end

    def candles_for(strike, type)
      typed = @option_data[type]
      return nil unless typed

      typed[strike]
    end
  end
end

