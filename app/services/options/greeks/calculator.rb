# frozen_string_literal: true

module Options
  module Greeks
    # Fallback-selection wrapper around BlackScholes: computes a real delta
    # from IV + DTE when both are available, degrading to the legacy
    # "within N strike-steps of ATM" heuristic (delta = 0.5 / 0.0) that the
    # strike-selection code used unconditionally before this existed.
    #
    # This is deliberately narrow in scope: it only ever runs when the
    # broker-supplied delta is missing (callers pass `option[:delta] ||
    # Calculator.estimate_delta(...)`), so it never overrides a live Greek
    # from DhanHQ — it only replaces a guess with a real calculation.
    module Calculator
      module_function

      DEFAULT_RISK_FREE_RATE = 0.065 # approx. Indian 91-day T-bill rate
      DEFAULT_ATM_WINDOW_STEPS = 2

      # @return [Float] absolute delta, always in [0.0, 1.0]
      def estimate_delta(spot_price:, strike_price:, option_type: nil, iv_pct: nil,
                         expiry_date: nil, days_to_expiry: nil, strike_step: nil,
                         atm_window_steps: DEFAULT_ATM_WINDOW_STEPS)
        dte = days_to_expiry || dte_from(expiry_date)

        if option_type.present? && iv_pct.to_f.positive? && dte&.positive? &&
           spot_price.to_f.positive? && strike_price.to_f.positive?
          greeks = BlackScholes.calculate(
            spot_price: spot_price,
            strike_price: strike_price,
            time_to_expiry_years: dte / 365.0,
            volatility: iv_pct.to_f / 100.0,
            option_type: option_type,
            risk_free_rate: DEFAULT_RISK_FREE_RATE
          )
          return greeks[:delta].abs
        end

        legacy_atm_fallback(spot_price: spot_price, strike_price: strike_price,
                            strike_step: strike_step, atm_window_steps: atm_window_steps)
      rescue StandardError => e
        Rails.logger.warn("[Options::Greeks::Calculator] estimate_delta falling back: #{e.class} - #{e.message}")
        legacy_atm_fallback(spot_price: spot_price, strike_price: strike_price,
                            strike_step: strike_step, atm_window_steps: atm_window_steps)
      end

      def dte_from(expiry_date)
        return nil if expiry_date.blank?

        date = expiry_date.respond_to?(:to_date) ? expiry_date.to_date : Date.parse(expiry_date.to_s)
        (date - Date.current).to_i
      rescue StandardError
        nil
      end

      # The original heuristic every call site used before internal Greeks
      # existed: ATM +/- N strike-steps gets an assumed delta of 0.5, else 0.0.
      def legacy_atm_fallback(spot_price:, strike_price:, strike_step:, atm_window_steps: DEFAULT_ATM_WINDOW_STEPS)
        return 0.0 unless spot_price.to_f.positive? && strike_price.to_f.positive? && strike_step.to_f.positive?

        atm = (spot_price.to_f / strike_step).round * strike_step
        (strike_price.to_f - atm).abs <= (strike_step * atm_window_steps) ? 0.5 : 0.0
      end
    end
  end
end
