# frozen_string_literal: true

module Options
  module IndexRules
    # Template Method: the three indices share every rule and differ only in their numbers.
    # A subclass supplies INDEX_KEY, STRIKE_STEP, MIN_VOLUME, MIN_PREMIUM, MAX_SPREAD_PCT,
    # ATM_DELTA, OTHER_STRIKE_DELTA and MOVE_THRESHOLD_POINTS,
    # and overrides #candidate_strikes or #premium_of where its behavior really differs.
    class Base
      def multiplier
        1
      end

      def lot_size
        Trading::LotCalculator.lot_size_for(self.class::INDEX_KEY)
      end

      def strike_step
        self.class::STRIKE_STEP
      end

      def atm(spot)
        (spot.to_f / strike_step).round * strike_step
      end

      def candidate_strikes(atm_strike, _strength = nil)
        [atm_strike]
      end

      def option_type(direction)
        direction == :bullish ? 'CE' : 'PE'
      end

      def valid_liquidity?(candidate)
        volume = candidate[:volume] || candidate['volume'] || 0
        volume.to_i >= self.class::MIN_VOLUME
      end

      def valid_spread?(candidate)
        bid = (candidate[:bid] || candidate['bid'] || 0).to_f
        ask = (candidate[:ask] || candidate['ask'] || 0).to_f
        return false if bid <= 0 || ask <= 0

        spread_pct = ((ask - bid) / ask)
        spread_pct <= self.class::MAX_SPREAD_PCT
      end

      def valid_premium?(candidate)
        premium_of(candidate) >= self.class::MIN_PREMIUM
      end

      # Assumed option delta used to turn an expected index move into an expected premium move.
      def delta_bucket(strike_type)
        strike_type == :ATM ? self.class::ATM_DELTA : self.class::OTHER_STRIKE_DELTA
      end

      # Minimum expected premium move (points) the permission level demands; nil when not allowed.
      def move_threshold_points(permission)
        self.class::MOVE_THRESHOLD_POINTS[permission]
      end

      private

      def premium_of(candidate)
        (candidate[:ltp] || candidate['ltp'] || 0).to_f
      end
    end
  end
end
