# frozen_string_literal: true

module Options
  module Greeks
    # Standalone Black-Scholes-Merton option pricing and Greeks model.
    #
    # The system has no internal Greeks computation today (see CLAUDE.md /
    # architecture review): delta, gamma, theta, vega and IV are sourced
    # entirely from the DhanHQ option chain response, with a crude heuristic
    # (delta = 0.5 within N strike-steps of ATM, else 0.0) used whenever that
    # data is missing. This module provides an independent, broker-agnostic
    # cross-check so strike-selection code can compute a real delta instead
    # of guessing when IV/DTE are available. It intentionally does not touch
    # or override live broker Greeks — see Options::Greeks::Calculator for
    # the fallback-selection logic that decides when to use this.
    module BlackScholes
      module_function

      MIN_TIME_TO_EXPIRY_YEARS = 1.0 / (365.0 * 24 * 60) # 1 minute floor, avoids div/0 at expiry
      MIN_VOLATILITY = 0.01
      MAX_VOLATILITY = 5.0
      MAX_IV_ITERATIONS = 100
      IV_PRICE_TOLERANCE = 1.0e-6

      ZERO_RESULT = { theoretical_price: 0.0, delta: 0.0, gamma: 0.0, theta: 0.0, vega: 0.0, rho: 0.0 }.freeze

      # @param spot_price [Numeric] underlying LTP
      # @param strike_price [Numeric]
      # @param time_to_expiry_years [Numeric] fraction of a year until expiry
      # @param volatility [Numeric] annualized IV as a decimal (0.15 == 15%)
      # @param option_type [Symbol, String] one of call/ce/c or put/pe/p (case-insensitive)
      # @param risk_free_rate [Numeric] annualized, decimal (default ~ Indian T-bill rate)
      # @param dividend_yield [Numeric] annualized, decimal (index carry; default 0)
      # @return [Hash] :theoretical_price, :delta, :gamma, :theta (per day), :vega (per 1% IV), :rho (per 1% rate)
      def calculate(spot_price:, strike_price:, time_to_expiry_years:, volatility:,
                    option_type:, risk_free_rate: 0.065, dividend_yield: 0.0)
        s = spot_price.to_f
        k = strike_price.to_f
        return ZERO_RESULT unless s.positive? && k.positive?

        t = [time_to_expiry_years.to_f, MIN_TIME_TO_EXPIRY_YEARS].max
        sigma = clamp_volatility(volatility)
        r = risk_free_rate.to_f
        q = dividend_yield.to_f
        call = call_option?(option_type)

        sqrt_t = Math.sqrt(t)
        d1 = (Math.log(s / k) + ((r - q + (0.5 * sigma * sigma)) * t)) / (sigma * sqrt_t)
        d2 = d1 - (sigma * sqrt_t)

        discount_r = Math.exp(-r * t)
        discount_q = Math.exp(-q * t)
        pdf_d1 = norm_pdf(d1)

        {
          theoretical_price: price_for(call, s, k, t, d1, d2, discount_r, discount_q).round(4),
          delta: delta_for(call, discount_q, d1).round(4),
          gamma: (discount_q * pdf_d1 / (s * sigma * sqrt_t)).round(6),
          theta: (theta_for(call, s, k, t, sigma, r, q, d1, d2, pdf_d1, discount_r, discount_q) / 365.0).round(4),
          vega: (s * discount_q * pdf_d1 * sqrt_t / 100.0).round(4),
          rho: (rho_for(call, k, t, discount_r, d2) / 100.0).round(4)
        }
      end

      # Solves for implied volatility given an observed market premium, via
      # Newton-Raphson with a bisection fallback when the Newton step
      # diverges or vega is too small to be numerically useful.
      #
      # @return [Float, nil] annualized IV as a decimal, or nil if it cannot be solved
      def implied_volatility(observed_premium:, spot_price:, strike_price:, time_to_expiry_years:,
                             option_type:, risk_free_rate: 0.065, dividend_yield: 0.0)
        target = observed_premium.to_f
        return nil unless target.positive? && spot_price.to_f.positive? && strike_price.to_f.positive?
        return nil if time_to_expiry_years.to_f <= 0

        sigma = newton_raphson_iv(target, spot_price, strike_price, time_to_expiry_years,
                                  option_type, risk_free_rate, dividend_yield)
        return sigma if sigma

        bisection_iv(target, spot_price, strike_price, time_to_expiry_years,
                     option_type, risk_free_rate, dividend_yield)
      end

      def call_option?(option_type)
        normalized = option_type.to_s.strip.upcase
        return true if %w[CALL CE C].include?(normalized)
        return false if %w[PUT PE P].include?(normalized)

        raise ArgumentError, "Unknown option_type: #{option_type.inspect}"
      end

      # Standard normal cumulative distribution function.
      def norm_cdf(x)
        0.5 * (1.0 + erf(x / Math.sqrt(2)))
      end

      # Standard normal probability density function.
      def norm_pdf(x)
        Math.exp(-0.5 * x * x) / Math.sqrt(2 * Math::PI)
      end

      # Abramowitz & Stegun 7.1.26 approximation (max error ~1.5e-7).
      def erf(x)
        sign = x.negative? ? -1.0 : 1.0
        x = x.abs

        a1 = 0.254829592
        a2 = -0.284496736
        a3 = 1.421413741
        a4 = -1.453152027
        a5 = 1.061405429
        p = 0.3275911

        t = 1.0 / (1.0 + (p * x))
        poly = (((((((a5 * t) + a4) * t) + a3) * t) + a2) * t) + a1
        y = 1.0 - (poly * t * Math.exp(-x * x))
        sign * y
      end

      def clamp_volatility(volatility)
        v = volatility.to_f
        return MIN_VOLATILITY if v < MIN_VOLATILITY
        return MAX_VOLATILITY if v > MAX_VOLATILITY

        v
      end

      def price_for(call, s, k, t, d1, d2, discount_r, discount_q)
        if call
          (s * discount_q * norm_cdf(d1)) - (k * discount_r * norm_cdf(d2))
        else
          (k * discount_r * norm_cdf(-d2)) - (s * discount_q * norm_cdf(-d1))
        end
      end

      def delta_for(call, discount_q, d1)
        call ? (discount_q * norm_cdf(d1)) : (discount_q * (norm_cdf(d1) - 1.0))
      end

      # rubocop:disable Metrics/ParameterLists
      def theta_for(call, s, k, t, sigma, r, q, d1, d2, pdf_d1, discount_r, discount_q)
        decay_term = -(s * sigma * discount_q * pdf_d1) / (2 * Math.sqrt(t))

        if call
          decay_term - (r * k * discount_r * norm_cdf(d2)) + (q * s * discount_q * norm_cdf(d1))
        else
          decay_term + (r * k * discount_r * norm_cdf(-d2)) - (q * s * discount_q * norm_cdf(-d1))
        end
      end
      # rubocop:enable Metrics/ParameterLists

      def rho_for(call, k, t, discount_r, d2)
        if call
          k * t * discount_r * norm_cdf(d2)
        else
          -k * t * discount_r * norm_cdf(-d2)
        end
      end

      # rubocop:disable Metrics/ParameterLists
      def newton_raphson_iv(target, spot_price, strike_price, time_to_expiry_years,
                            option_type, risk_free_rate, dividend_yield)
        sigma = 0.25

        MAX_IV_ITERATIONS.times do
          result = calculate(
            spot_price: spot_price, strike_price: strike_price,
            time_to_expiry_years: time_to_expiry_years, volatility: sigma,
            option_type: option_type, risk_free_rate: risk_free_rate, dividend_yield: dividend_yield
          )
          price_diff = result[:theoretical_price] - target
          return sigma.round(4) if price_diff.abs < IV_PRICE_TOLERANCE

          vega_per_unit = result[:vega] * 100.0 # undo the "per 1% move" scaling for the raw derivative
          break if vega_per_unit.abs < 1.0e-8

          next_sigma = sigma - (price_diff / vega_per_unit)
          break if !next_sigma.finite? || next_sigma <= 0 || next_sigma > MAX_VOLATILITY

          sigma = next_sigma
        end

        nil
      end
      # rubocop:enable Metrics/ParameterLists

      # rubocop:disable Metrics/ParameterLists
      def bisection_iv(target, spot_price, strike_price, time_to_expiry_years,
                       option_type, risk_free_rate, dividend_yield)
        low = MIN_VOLATILITY
        high = MAX_VOLATILITY

        MAX_IV_ITERATIONS.times do
          mid = (low + high) / 2.0
          price = calculate(
            spot_price: spot_price, strike_price: strike_price,
            time_to_expiry_years: time_to_expiry_years, volatility: mid,
            option_type: option_type, risk_free_rate: risk_free_rate, dividend_yield: dividend_yield
          )[:theoretical_price]

          diff = price - target
          return mid.round(4) if diff.abs < IV_PRICE_TOLERANCE

          if diff.positive?
            high = mid
          else
            low = mid
          end
        end

        nil
      end
      # rubocop:enable Metrics/ParameterLists

      private_class_method :price_for, :delta_for, :theta_for, :rho_for,
                           :newton_raphson_iv, :bisection_iv, :clamp_volatility
    end
  end
end
