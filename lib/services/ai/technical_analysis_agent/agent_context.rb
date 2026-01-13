# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Agent Context: Stores structured facts, not raw DhanHQ JSON
      # This is a class, not a module, so it can be instantiated
      class AgentContext
        attr_accessor :intent, :underlying_symbol, :resolved_instrument,
                      :ltp, :filtered_strikes, :indicators, :tool_history,
                      :confidence, :derivatives_needed, :timeframe_hint,
                      :ambiguity_passes

        def initialize(intent_data = {})
          @intent = (intent_data[:intent] || intent_data['intent'] || :general).to_sym
          @underlying_symbol = intent_data[:underlying_symbol] || intent_data['underlying_symbol']
          @resolved_instrument = nil
          @ltp = nil
          @filtered_strikes = [] # Only ATM ±1 ±2 for options
          @indicators = {} # Aggregated, not raw
          @tool_history = []
          @confidence = (intent_data[:confidence] || intent_data['confidence'] || 0.0).to_f
          @derivatives_needed = intent_data[:derivatives_needed] || intent_data['derivatives_needed'] || false
          @timeframe_hint = intent_data[:timeframe_hint] || intent_data['timeframe_hint'] || '15m'
          @ambiguity_passes = 0
        end

        def add_observation(tool_name, tool_input, tool_result)
          # Store structured facts, not raw JSON
          observation = {
            tool: tool_name,
            input: tool_input,
            result: extract_facts(tool_result) # Extract only key facts
          }
          @tool_history << observation
        end

        def extract_facts(tool_result)
          # Extract only essential facts from tool result
          # DO NOT store raw OHLC arrays or full option chains
          return tool_result unless tool_result.is_a?(Hash)

          facts = {}
          facts[:ltp] = tool_result[:ltp] || tool_result['ltp'] if tool_result[:ltp] || tool_result['ltp']
          if tool_result[:indicators] || tool_result['indicators']
            facts[:indicators] =
              aggregate_indicators(tool_result)
          end
          facts[:strikes] = filter_strikes_for_context(tool_result[:strikes] || tool_result['strikes']) if tool_result[:strikes] || tool_result['strikes']
          if tool_result[:instrument_id] || tool_result['instrument_id']
            facts[:instrument_id] =
              tool_result[:instrument_id] || tool_result['instrument_id']
          end
          facts[:error] = tool_result[:error] || tool_result['error'] if tool_result[:error] || tool_result['error']
          facts
        end

        def aggregate_indicators(tool_result)
          # Extract only aggregated indicator values, not raw data
          indicators = tool_result[:indicators] || tool_result['indicators'] || {}
          return {} unless indicators.is_a?(Hash)

          aggregated = {}
          indicators.each do |timeframe, tf_indicators|
            aggregated[timeframe] = {}
            tf_indicators.each do |name, value|
              # Store only the value, not raw arrays
              aggregated[timeframe][name] = if value.is_a?(Hash)
                                              value.select { |k, _v| %w[value signal direction].include?(k.to_s) }
                                            else
                                              value
                                            end
            end
          end
          aggregated
        end

        def filter_strikes_for_context(strikes)
          # Already filtered to ATM ±1 ±2, just return as-is
          return [] unless strikes.is_a?(Array)

          strikes.first(5) # Max 5 strikes in context
        end

        def ready_for_analysis?
          # Check if we have minimum required data
          case @intent
          when :swing_trading
            @resolved_instrument && @ltp && @indicators.any?
          when :options_buying
            @resolved_instrument && @ltp && @filtered_strikes.any? && @indicators.any?
          when :intraday
            @resolved_instrument && @ltp && @indicators.any?
          else
            @resolved_instrument && @ltp
          end
        end

        def summary
          # Compact summary for final analysis
          {
            intent: @intent,
            symbol: @underlying_symbol,
            instrument_id: @resolved_instrument&.id,
            ltp: @ltp,
            indicators_count: @indicators.keys.length,
            strikes_count: @filtered_strikes.length,
            tools_called: @tool_history.length
          }
        end
      end
    end
  end
end
