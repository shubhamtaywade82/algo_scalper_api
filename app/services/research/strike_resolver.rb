# frozen_string_literal: true

module Research
  # Pure strike-selection math for the research pipeline. Kept separate from
  # app/services/options/index_rules/* (the live strike-selection path) so
  # research experimentation never risks touching live entry behaviour.
  class StrikeResolver
    STRIKE_STEP = {
      "NIFTY" => 50,
      "BANKNIFTY" => 100,
      "SENSEX" => 100
    }.freeze

    DEFAULT_STEP = 50

    class << self
      def strike_step(symbol)
        STRIKE_STEP.fetch(symbol.to_s.upcase, DEFAULT_STEP)
      end

      def atm(symbol:, spot:)
        step = strike_step(symbol)
        (spot.to_f / step).round * step
      end

      # Builds candidate strikes from ATM-max_distance to ATM+max_distance
      # (inclusive), for a given option_type. `distance` is always signed by
      # absolute strike direction (+ = higher strike), independent of
      # option_type, so the same strike_label means the same actual_strike
      # for both CE and PE.
      def candidates(symbol:, spot:, option_type:, max_distance: 2)
        step = strike_step(symbol)
        atm_strike = atm(symbol: symbol, spot: spot)

        (-max_distance..max_distance).map do |distance|
          {
            distance: distance,
            strike_label: label_for(distance),
            actual_strike: atm_strike + (distance * step),
            dhan_strike_param: dhan_strike_param(option_type: option_type, distance: distance)
          }
        end
      end

      def label_for(distance)
        return "ATM" if distance.zero?

        distance.positive? ? "ATM+#{distance}" : "ATM#{distance}"
      end

      # DhanHQ's expired-options API expects the strike param in ATM-relative
      # format ("ATM", "ATM+1", "ATM-1", …) regardless of option type — the
      # API resolves moneyness internally.  This is distinct from
      # Research::StrikeResolver#label_for only in that label_for returns
      # "ATM-2" (Ruby string-interpolates -2) while Dhan requires "ATM-2" as
      # well — they happen to be the same format.
      def dhan_strike_param(option_type:, distance:)
        label_for(distance)
      end
    end
  end
end
