# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Decision Engine: Rule-based tool selection (NOT LLM)
      module DecisionEngine
        def resolve_instrument_deterministically(context)
          symbol = context.underlying_symbol
          return nil unless symbol

          # Find all matching instruments
          candidates = Instrument.where(underlying_symbol: symbol.upcase)

          if candidates.count > 1
            # Disambiguate based on intent
            case context.intent
            when :swing_trading
              # Prefer EQUITY for swing trading
              candidates.find { |i| i.segment == 'equity' } || candidates.first
            when :options_buying
              # Prefer INDEX for options (NIFTY, BANKNIFTY) or stock underlying
              candidates.find { |i| i.segment == 'index' } ||
                candidates.find { |i| i.segment == 'equity' } ||
                candidates.first
            when :intraday
              # Prefer INDEX for intraday indices
              candidates.find { |i| i.segment == 'index' } || candidates.first
            else
              candidates.first
            end
          else
            candidates.first
          end
        end

        def narrow_option_chain(context, full_chain_result)
          # Extract spot price
          spot = context.ltp || full_chain_result[:spot] || full_chain_result['spot']
          return [] unless spot

          strikes = full_chain_result[:strikes] || full_chain_result['strikes'] || []
          return [] unless strikes.is_a?(Array) && strikes.any?

          # Calculate ATM (round to nearest 50 for indices, 5 for stocks)
          round_to = if %w[NIFTY BANKNIFTY SENSEX].include?(context.underlying_symbol&.upcase)
                       50
                     else
                       5
                     end
          atm_strike = (spot.to_f / round_to).round * round_to

          # Filter to ATM ±1 ±2 only
          filtered = strikes.select do |strike|
            strike_value = strike[:strike] || strike['strike'] || strike
            strike_diff = (strike_value.to_f - atm_strike).abs
            strike_diff <= (round_to * 2) # ATM, ATM±1, ATM±2
          end

          # Store filtered strikes in context
          context.filtered_strikes = filtered.first(5) # Max 5 strikes
          filtered.first(5)
        end

        def narrow_for_swing_trading(context)
          # Force EQUITY segment
          if context.resolved_instrument&.segment != 'equity'
            context.resolved_instrument = Instrument
                                          .where(underlying_symbol: context.underlying_symbol)
                                          .where(segment: 'equity')
                                          .first
          end

          # Use higher timeframes (15m, 1h, daily)
          context.timeframe_hint = %w[15m 1h daily].find { |tf| tf == context.timeframe_hint } || '15m'

          # Ignore derivatives
          context.derivatives_needed = false
        end

        def next_tool(context)
          # Step 1: Resolve instrument if not done
          unless context.resolved_instrument
            instrument = resolve_instrument_deterministically(context)
            unless instrument
              return { tool: 'abort', args: { reason: "Instrument not found: #{context.underlying_symbol}" } }
            end

            context.resolved_instrument = instrument
            return { tool: 'get_ltp', args: { instrument_id: instrument.id } }

          end

          # Step 2: Get LTP if not available
          return { tool: 'get_ltp', args: { instrument_id: context.resolved_instrument.id } } unless context.ltp

          # Step 3: Based on intent, fetch appropriate data
          case context.intent
          when :options_buying
            # For options: fetch chain, then indicators
            # Check if we've already tried fetch_option_chain and it failed
            option_chain_attempts = context.tool_history.count { |obs| obs[:tool] == 'fetch_option_chain' }
            option_chain_failed = context.tool_history.any? do |obs|
              obs[:tool] == 'fetch_option_chain' && obs[:result].is_a?(Hash) && obs[:result][:error]
            end

            # Try option chain first (max 2 attempts), but don't block on it
            if context.filtered_strikes.empty? && option_chain_attempts < 2
              return { tool: 'fetch_option_chain', args: { instrument_id: context.resolved_instrument.id } }
            end

            # If option chain failed or we have strikes, fetch indicators
            # Use 15m as primary (25 candles/day) - cleaner signals for options trading
            # 5m (75 candles/day) is too noisy and generates too many false signals
            if context.indicators.empty?
              return { tool: 'compute_indicators', args: { instrument_id: context.resolved_instrument.id, timeframes: %w[15m 1h] } }
            end
          when :swing_trading
            # For swing: use higher timeframes, no derivatives
            narrow_for_swing_trading(context)
            if context.indicators.empty?
              return { tool: 'compute_indicators', args: { instrument_id: context.resolved_instrument.id, timeframes: %w[15m 1h] } }
            end
          when :intraday
            # For intraday: use 15m as primary (25 candles/day) for cleaner signals
            # 5m (75 candles/day) is too noisy for options trading analysis
            if context.indicators.empty?
              return { tool: 'compute_indicators', args: { instrument_id: context.resolved_instrument.id, timeframes: %w[15m 1h] } }
            end
          else
            # General query: just get indicators if missing
            if context.indicators.empty?
              return { tool: 'compute_indicators', args: { instrument_id: context.resolved_instrument.id, timeframes: ['15m'] } }
            end
          end

          # Step 4: Ready for analysis
          return { tool: 'finalize', args: {} } if context.ready_for_analysis?

          # Default: abort if we can't determine next step
          { tool: 'abort', args: { reason: 'Cannot determine next step - insufficient data' } }
        end

        def calculate_atm_strike(spot, strikes)
          # Calculate ATM strike (round to nearest 50 for indices, 5 for stocks)
          round_to = if spot.to_f > 10_000 # Likely an index
                       50
                     else
                       5
                     end
          (spot.to_f / round_to).round * round_to
        end
      end
    end
  end
end
