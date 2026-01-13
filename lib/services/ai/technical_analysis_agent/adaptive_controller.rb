# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Adaptive Controller: Self-correcting logic with payload reduction
      module AdaptiveController
        MAX_PAYLOAD_SIZE = ENV.fetch('AI_MAX_PAYLOAD_SIZE', '2000').to_i # characters
        MAX_AMBIGUITY_PASSES = 2
        MAX_REPEAT_STEPS = 3

        def adapt_tool_result(context, tool_name, tool_result)
          # Rule 1: Reduce payload if too large
          if tool_result.to_json.length > MAX_PAYLOAD_SIZE
            Rails.logger.warn("[AdaptiveController] Payload too large (#{tool_result.to_json.length} chars), reducing...")
            tool_result = reduce_payload(context, tool_name, tool_result)
          end

          # Rule 2: Handle ambiguity
          if ambiguous?(tool_result) && context.ambiguity_passes >= MAX_AMBIGUITY_PASSES
            Rails.logger.warn('[AdaptiveController] Ambiguity detected, narrowing deterministically...')
            tool_result = narrow_deterministically(context, tool_result)
            context.ambiguity_passes += 1
          elsif ambiguous?(tool_result)
            context.ambiguity_passes += 1
          end

          # Rule 3: Detect repeating states
          if repeating_step?(context, tool_name)
            Rails.logger.warn("[AdaptiveController] Repeating step detected: #{tool_name}")
            return { error: 'NO_TRADE', reason: 'Repeating steps detected - insufficient data' }
          end

          tool_result
        end

        def reduce_payload(context, tool_name, tool_result)
          case tool_name
          when 'fetch_option_chain'
            # Filter to ATM ±1 ±2 only (use DecisionEngine method)
            narrowed = narrow_option_chain(context, tool_result)
            spot = context.ltp || tool_result[:spot] || tool_result['spot']
            {
              spot: spot,
              atm_strike: calculate_atm_strike(spot, narrowed),
              strikes: narrowed
            }
          when 'fetch_candles', 'get_historical_data'
            # Keep only last N candles
            result = tool_result.dup
            if result[:candles] || result['candles']
              candles = result[:candles] || result['candles']
              result[:candles] = candles.is_a?(Array) ? candles.last(50) : candles
              result['candles'] = result[:candles] if result['candles']
            end
            result
          when 'compute_indicators', 'get_comprehensive_analysis'
            # Aggregate indicators, remove raw data
            aggregate_indicators_for_context(tool_result)
          else
            tool_result
          end
        end

        def ambiguous?(tool_result)
          # Check if result is ambiguous (multiple instruments, unclear data)
          return false unless tool_result.is_a?(Hash)

          # Multiple instruments found
          return true if tool_result[:instruments]&.length.to_i > 1
          return true if tool_result['instruments']&.length.to_i > 1

          # Unclear option chain
          if tool_result[:strikes] || tool_result['strikes']
            strikes = tool_result[:strikes] || tool_result['strikes']
            return true if strikes.is_a?(Array) && strikes.length > 20
          end

          false
        end

        def narrow_deterministically(context, tool_result)
          # Narrow based on intent (use DecisionEngine methods)
          case context.intent
          when :swing_trading
            # Force equity, higher timeframes
            narrow_for_swing_trading(context)
          when :options_buying
            # Filter option chain
            narrow_option_chain(context, tool_result) if tool_result[:strikes] || tool_result['strikes']
          end

          tool_result
        end

        def repeating_step?(context, tool_name)
          recent_tools = context.tool_history.last(MAX_REPEAT_STEPS).pluck(:tool)
          recent_tools.count(tool_name) >= MAX_REPEAT_STEPS
        end

        def aggregate_indicators_for_context(tool_result)
          # Extract only aggregated indicator values
          result = tool_result.dup
          if result[:indicators] || result['indicators']
            indicators = result[:indicators] || result['indicators']
            aggregated = {}
            indicators.each do |timeframe, tf_indicators|
              aggregated[timeframe] = {}
              tf_indicators.each do |name, value|
                aggregated[timeframe][name] = if value.is_a?(Hash)
                                                value.select { |k, _v| %w[value signal direction].include?(k.to_s) }
                                              else
                                                value
                                              end
              end
            end
            result[:indicators] = aggregated
            result['indicators'] = aggregated
          end
          result
        end
      end
    end
  end
end
