# frozen_string_literal: true

module Options
  module IndexRules
    # Index-specific rules for NIFTY
    class Nifty
      MIN_VOLUME = 30_000
      MIN_PREMIUM = 25.0
      MAX_SPREAD_PCT = 0.003 # 0.3%

      def multiplier
        1
      end

      def lot_size
        75
      end

      def atm(spot)
        (spot.to_f / 50).round * 50
      end

      def candidate_strikes(atm_strike, _strength = nil)
        [atm_strike, atm_strike + 50]
      end

      def option_type(direction)
        direction == :bullish ? 'CE' : 'PE'
      end

      def valid_liquidity?(candidate)
        volume = candidate[:volume] || candidate['volume'] || 0
        volume.to_i >= MIN_VOLUME
      end

      def valid_spread?(candidate)
        bid = (candidate[:bid] || candidate['bid'] || 0).to_f
        ask = (candidate[:ask] || candidate['ask'] || 0).to_f
        return false if bid <= 0 || ask <= 0

        spread_pct = ((ask - bid) / ask.to_f)
        spread_pct <= MAX_SPREAD_PCT
      end

      def valid_premium?(candidate)
        premium = (candidate[:ltp] || candidate['ltp'] || candidate[:last_price] || 0).to_f
        premium >= MIN_PREMIUM
      end
    end
  end
end
