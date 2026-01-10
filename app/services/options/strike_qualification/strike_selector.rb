# frozen_string_literal: true

module Options
  module StrikeQualification
    # Context-aware ATM / ATM±1 strike selector (deterministic).
    #
    # Output shape (MANDATORY):
    #   { ok: true, strike: Integer, strike_type: Symbol, atm_strike: Integer }
    #
    # Hard rules:
    # - permission=:execution_only => FORCE ATM only
    # - SENSEX => ATM±1 only allowed when permission==:full_deploy
    # - If chosen strike fails basic chain presence/liquidity => fallback to ATM
    # - If ATM also fails => BLOCK
    class StrikeSelector < ApplicationService
      VALID_SIDES = %i[CE PE].freeze
      VALID_PERMISSIONS = %i[execution_only scale_ready full_deploy].freeze
      VALID_TRENDS = %i[bullish bearish chop neutral range].freeze

      def call(index_key:, side:, permission:, spot:, option_chain:, trend: nil)
        index = index_key.to_s.strip.upcase
        side_sym = side.to_s.strip.upcase.to_sym
        perm = permission.to_s.strip.downcase.to_sym
        trend_sym = trend.nil? ? nil : trend.to_s.strip.downcase.to_sym

        return blocked('invalid_side') unless VALID_SIDES.include?(side_sym)
        return blocked('invalid_permission') unless VALID_PERMISSIONS.include?(perm)
        return blocked('invalid_spot') unless spot.to_f.positive?
        return blocked('invalid_chain') unless option_chain.is_a?(Hash)
        return blocked('invalid_trend') if trend_sym && !VALID_TRENDS.include?(trend_sym)

        step = strike_step_for(index)
        atm_strike = round_to_step(spot.to_f, step)

        desired = desired_strike(
          index: index,
          side: side_sym,
          permission: perm,
          trend: trend_sym,
          atm_strike: atm_strike,
          step: step
        )

        if liquid_in_chain?(option_chain: option_chain, strike: desired[:strike], side: side_sym)
          return ok(desired.merge(atm_strike: atm_strike))
        end

        # Fallback to ATM.
        if liquid_in_chain?(option_chain: option_chain, strike: atm_strike, side: side_sym)
          return ok(strike: atm_strike, strike_type: :ATM, atm_strike: atm_strike)
        end

        blocked('no_liquid_atm')
      rescue StandardError => e
        Rails.logger.error("[Options::StrikeQualification::StrikeSelector] #{e.class} - #{e.message}")
        blocked('error')
      end

      private

      def strike_step_for(index)
        case index
        when 'NIFTY' then 50
        when 'SENSEX' then 100
        else 50
        end
      end

      def round_to_step(value, step)
        ((value / step.to_f).round * step).to_i
      end

      def desired_strike(index:, side:, permission:, trend:, atm_strike:, step:)
        return { strike: atm_strike, strike_type: :ATM } if permission == :execution_only
        return { strike: atm_strike, strike_type: :ATM } if index == 'SENSEX' && permission != :full_deploy
        return { strike: atm_strike, strike_type: :ATM } if %i[chop neutral range].include?(trend)

        if trend == :bearish
          return { strike: atm_strike, strike_type: :ATM } if side == :CE
          return { strike: atm_strike - step, strike_type: :ATM_MINUS_1 }
        end

        if trend == :bullish
          return { strike: atm_strike, strike_type: :ATM } if side == :PE
          return { strike: atm_strike + step, strike_type: :ATM_PLUS_1 }
        end

        # Default when trend is unknown: conservative ATM.
        { strike: atm_strike, strike_type: :ATM }
      end

      def liquid_in_chain?(option_chain:, strike:, side:)
        data = option_data_for(option_chain: option_chain, strike: strike, side: side)
        return false unless data.is_a?(Hash)

        ltp = data['last_price']&.to_f
        oi = data['oi']&.to_i
        bid = data['top_bid_price']&.to_f
        ask = data['top_ask_price']&.to_f

        return false unless ltp&.positive?
        return false unless oi&.positive?

        # Basic spread sanity check (hard reject only for obviously broken books).
        if bid&.positive? && ask&.positive?
          spread = ask - bid
          return false if spread.negative?
          return false if spread > (ltp * 0.15) # 15% hard reject
        end

        true
      rescue StandardError
        false
      end

      def option_data_for(option_chain:, strike:, side:)
        strike_key = strike.to_i.to_s
        strike_data = option_chain[strike_key] || option_chain[strike_key.to_f.to_s] || option_chain[strike_key.to_i]
        return nil unless strike_data.is_a?(Hash)

        side_key = side == :CE ? 'ce' : 'pe'
        strike_data[side_key]
      end

      def ok(payload)
        { ok: true }.merge(payload)
      end

      def blocked(reason)
        { ok: false, reason: reason }
      end
    end
  end
end

