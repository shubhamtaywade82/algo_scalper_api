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

        # Get available strikes from the filtered chain (only strikes that exist)
        # Handle different key formats in option chain
        available_strikes = option_chain.keys.map do |k|
          k.to_f
        rescue StandardError
          nil
        end.compact.to_set

        desired = desired_strike(
          index: index,
          side: side_sym,
          permission: perm,
          trend: trend_sym,
          atm_strike: atm_strike,
          step: step
        )

        # Check if desired strike exists in chain before checking liquidity
        desired_strike_float = desired[:strike].to_f
        if available_strikes.include?(desired_strike_float)
          if liquid_in_chain?(option_chain: option_chain, strike: desired[:strike], side: side_sym)
            return ok(desired.merge(atm_strike: atm_strike))
          end
        end

        # Fallback to ATM if it exists in chain
        atm_strike_float = atm_strike.to_f
        if available_strikes.include?(atm_strike_float)
          if liquid_in_chain?(option_chain: option_chain, strike: atm_strike, side: side_sym)
            return ok(strike: atm_strike, strike_type: :ATM, atm_strike: atm_strike)
          end
        end

        # Enhanced error reporting
        atm_data = option_data_for(option_chain: option_chain, strike: atm_strike, side: side_sym)
        if atm_data.nil?
          Rails.logger.warn("[StrikeSelector] ATM strike #{atm_strike} #{side_sym} not found in option chain for #{index}")
          return blocked('atm_strike_not_in_chain')
        end

        ltp = atm_data['last_price']&.to_f
        oi = atm_data['oi']&.to_i
        Rails.logger.warn(
          "[StrikeSelector] ATM strike #{atm_strike} #{side_sym} failed liquidity check " \
          "(LTP: #{ltp.inspect}, OI: #{oi.inspect}) for #{index}"
        )
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
        when 'BANKNIFTY' then 100
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
        unless data.is_a?(Hash)
          Rails.logger.debug { "[StrikeSelector] No option data found for strike #{strike} #{side}" }
          return false
        end

        ltp = data['last_price']&.to_f
        oi = data['oi']&.to_i
        bid = data['top_bid_price']&.to_f
        ask = data['top_ask_price']&.to_f

        # Check if strike exists in chain (basic presence check)
        # If strike exists but has no LTP, it might be market closed - be more lenient
        strike_exists = !data.empty?

        # For paper trading or when market might be closed, be more lenient
        # Allow if strike exists in chain, even if LTP/OI are 0 (will use bid/ask or fallback)
        paper_trading = AlgoConfig.fetch.dig(:paper_trading, :enabled) == true

        # In paper mode, if strike exists in chain, allow it even with 0 LTP/OI
        # EntryGuard will resolve LTP from REST API if needed
        if paper_trading && strike_exists && (ltp.nil? || ltp.zero?)
          Rails.logger.debug { "[StrikeSelector] Paper mode: Allowing strike #{strike} #{side} with 0 LTP (will resolve via API)" }
          return true
        end

        # Standard liquidity checks (for live trading or when LTP is available)
        unless ltp&.positive?
          Rails.logger.debug { "[StrikeSelector] Strike #{strike} #{side} has invalid LTP: #{ltp.inspect}" }
          return false
        end

        # OI check - be lenient if OI is 0 but strike exists (might be new contract)
        unless oi&.positive?
          if paper_trading && strike_exists
            Rails.logger.debug { "[StrikeSelector] Paper mode: Allowing strike #{strike} #{side} with 0 OI" }
            return true
          end
          Rails.logger.debug { "[StrikeSelector] Strike #{strike} #{side} has invalid OI: #{oi.inspect}" }
          return false
        end

        # Basic spread sanity check (hard reject only for obviously broken books).
        if bid&.positive? && ask&.positive?
          spread = ask - bid
          if spread.negative?
            Rails.logger.debug { "[StrikeSelector] Strike #{strike} #{side} has negative spread: #{spread}" }
            return false
          end
          if spread > (ltp * 0.15) # 15% hard reject
            Rails.logger.debug { "[StrikeSelector] Strike #{strike} #{side} has wide spread: #{spread} (> #{ltp * 0.15})" }
            return false
          end
        end

        true
      rescue StandardError => e
        Rails.logger.debug { "[StrikeSelector] Error checking liquidity for strike #{strike} #{side}: #{e.class} - #{e.message}" }
        false
      end

      def option_data_for(option_chain:, strike:, side:)
        # Try multiple key formats to find strike data
        strike_int = strike.to_i
        strike_float = strike.to_f

        # Try: string integer, string float, integer, float, formatted float (e.g., "25750.000000")
        possible_keys = [
          strike_int.to_s,
          strike_float.to_s,
          format('%.6f', strike_float),  # Format like "25750.000000"
          format('%.2f', strike_float),  # Format like "25750.00"
          strike_int,
          strike_float,
          strike_int.to_s.to_sym, # Symbol keys sometimes
          strike_float.to_s.to_sym
        ]

        strike_data = nil
        found_key = nil

        possible_keys.each do |key|
          next unless option_chain.key?(key)

          strike_data = option_chain[key]
          found_key = key
          break
        end

        # If exact match not found, try fuzzy matching (find closest key)
        unless strike_data.is_a?(Hash)
          # Try to find key that matches when converted to float
          option_chain.keys.each do |key|
            key_float = key.to_f
            next unless (key_float - strike_float).abs < 0.01 # Within 0.01 tolerance

            strike_data = option_chain[key]
            found_key = key
            break
          end
        end

        unless strike_data.is_a?(Hash)
          Rails.logger.debug do
            "[StrikeSelector] Strike #{strike} not found in chain. " \
              "Tried keys: #{possible_keys.first(6).inspect}. " \
              "Available keys (sample): #{option_chain.keys.first(5).inspect}"
          end
          return nil
        end

        side_key = side == :CE ? 'ce' : 'pe'
        option_data = strike_data[side_key] || strike_data[side_key.to_sym]

        unless option_data
          Rails.logger.debug do
            "[StrikeSelector] #{side} option not found for strike #{strike} (key: #{found_key}). " \
              "Available keys in strike_data: #{strike_data.keys.inspect}"
          end
        end

        option_data
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
