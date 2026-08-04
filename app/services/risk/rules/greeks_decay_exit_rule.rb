# frozen_string_literal: true

module Risk
  module Rules
    # Greeks Decay Exit Rule — exits when the position's OWN contract greeks show
    # the trade is structurally bleeding, not just when price/PnL crosses a threshold
    #
    # PROBLEM: Every other exit in this stack reasons about price/PnL (spot move,
    # premium momentum, time elapsed). None of them ask the option chain "what is THIS
    # specific contract's theta/delta doing right now?" — even though greeks are fetched
    # and scored at ENTRY time (Options::ChainAnalyzer#analyze_strike). A position can
    # be flat-to-slightly-down on price while its theta burn accelerates (gamma zone,
    # near expiry) or its delta has collapsed toward zero (spot moved away, the option
    # is becoming a lottery ticket no longer expressing the original directional thesis)
    # — both real, greeks-visible deterioration that price-action proxies catch late
    # or not at all.
    #
    # This rule fetches the position's own contract's live greeks from the (already
    # cached, ~2min-fresh) option chain — see Instrument#fetch_option_chain — and exits
    # on either:
    #
    #   1. THETA BURN — |theta| as a fraction of current premium exceeds a configurable
    #      daily-burn-rate ceiling AND the position isn't comfortably profitable enough
    #      to absorb it. ("This contract is now losing >X% of its value to time decay
    #      per day — the math no longer works in a buyer's favor.")
    #
    #   2. DELTA COLLAPSE — delta magnitude has fallen below a floor (the option has
    #      drifted OTM / lost directional sensitivity) while the position is underwater.
    #      ("The thesis this trade expressed no longer has teeth — cut it before theta
    #      finishes the job.")
    #
    # Fails CLOSED to no-op on any missing/stale greeks data — this rule only acts when
    # it has real broker-sourced greeks for the exact contract, never on a guess.
    #
    # Config (config/algo.yml under risk.greeks_decay_exit):
    #   greeks_decay_exit:
    #     enabled: true
    #     theta_burn_pct_of_premium: 0.08   # |theta|/premium >= 8%/day → burn alarm
    #     theta_burn_pnl_immunity_pct: 0.10 # positions up >=10% are immune to the theta leg
    #     delta_floor: 0.20                 # |delta| below this while losing → collapse alarm
    #     delta_collapse_pnl_ceiling_pct: -0.03  # only fires when pnl_pct <= this (i.e. losing)
    #
    # Priority: 31 — alongside PremiumMomentumFailureRule (30)/TakeProfitRule (30) in the
    # "is this trade structurally still working" band, before the trailing/lock layers
    # (33+) get a say on a trade that greeks say is already dead.
    class GreeksDecayExitRule < BaseRule
      PRIORITY = 31

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        tracker = context.tracker
        instrument = tracker&.instrument
        return no_action_result unless instrument

        greeks = current_contract_greeks(instrument)
        return no_action_result unless greeks

        pnl_pct = context.pnl_pct.to_f
        premium = context.current_ltp.to_f

        theta_result = theta_burn_check(greeks: greeks, premium: premium, pnl_pct: pnl_pct)
        return theta_result if theta_result

        delta_result = delta_collapse_check(greeks: greeks, pnl_pct: pnl_pct)
        return delta_result if delta_result

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[GreeksDecayExitRule] Error: #{e.class} - #{e.message}")
        skip_result
      end

      def enabled?(_context = nil)
        cfg.fetch(:enabled, true) != false
      end

      private

      def theta_burn_check(greeks:, premium:, pnl_pct:)
        theta = greeks[:theta]
        return nil unless theta && premium.positive?
        return nil if pnl_pct >= theta_burn_pnl_immunity_pct

        burn_ratio = theta.abs / premium
        return nil if burn_ratio < theta_burn_pct_of_premium

        exit_result(
          reason: "GREEKS_THETA_BURN (theta #{theta.round(2)} = #{(burn_ratio * 100).round(1)}% of premium " \
                  "#{premium.round(2)}/day, pnl #{(pnl_pct * 100).round(2)}%)",
          metadata: {
            path: 'greeks_theta_burn',
            theta: theta,
            premium: premium,
            burn_ratio: burn_ratio.round(4),
            pnl_pct: pnl_pct
          }
        )
      end

      def delta_collapse_check(greeks:, pnl_pct:)
        delta = greeks[:delta]
        return nil unless delta
        return nil if pnl_pct > delta_collapse_pnl_ceiling_pct

        delta_magnitude = delta.abs
        return nil if delta_magnitude >= delta_floor

        exit_result(
          reason: "GREEKS_DELTA_COLLAPSE (delta #{delta.round(3)}, |delta| #{delta_magnitude.round(3)} < " \
                  "floor #{delta_floor}, pnl #{(pnl_pct * 100).round(2)}%)",
          metadata: {
            path: 'greeks_delta_collapse',
            delta: delta,
            delta_floor: delta_floor,
            pnl_pct: pnl_pct
          }
        )
      end

      # Reuses Instrument#fetch_option_chain's existing ~2min cache (same path used by
      # Signal::Engine#fetch_real_atm_iv) — no extra per-tick chain fetches.
      def current_contract_greeks(instrument)
        strike = instrument.strike_price
        option_type = instrument.option_type&.downcase
        expiry = instrument.expiry_date
        return nil unless strike && option_type.present? && expiry

        chain_data = instrument.fetch_option_chain(expiry)
        oc = chain_data.is_a?(Hash) ? chain_data[:oc] : nil
        return nil unless oc.present?

        contract = oc[strike.to_f.to_s]&.dig(option_type)
        greeks = contract&.dig('greeks')
        return nil unless greeks.is_a?(Hash)

        delta = greeks['delta']&.to_f
        theta = greeks['theta']&.to_f
        return nil unless delta || theta

        { delta: delta, theta: theta, gamma: greeks['gamma']&.to_f, vega: greeks['vega']&.to_f }
      rescue StandardError => e
        Rails.logger.warn("[GreeksDecayExitRule] greeks fetch error: #{e.class} - #{e.message}")
        nil
      end

      def theta_burn_pct_of_premium
        cfg.fetch(:theta_burn_pct_of_premium, 0.08).to_f
      end

      def theta_burn_pnl_immunity_pct
        cfg.fetch(:theta_burn_pnl_immunity_pct, 0.10).to_f
      end

      def delta_floor
        cfg.fetch(:delta_floor, 0.20).to_f
      end

      def delta_collapse_pnl_ceiling_pct
        cfg.fetch(:delta_collapse_pnl_ceiling_pct, -0.03).to_f
      end

      def cfg
        AlgoConfig.fetch.dig(:risk, :greeks_decay_exit) || {}
      rescue StandardError
        {}
      end
    end
  end
end
