# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Agent Runner: Main orchestration loop for intent-aware, micro-step ReAct agent
      module AgentRunner
        def run_agent_loop(query:, stream: false, &)
          # Step 1: Resolve intent (LLM - small)
          intent_data = resolve_intent(query)
          context = AgentContext.new(intent_data)

          yield("🔍 [Intent] Resolved: #{intent_data[:intent]} (confidence: #{(intent_data[:confidence] * 100).round}%)\n") if block_given?
          yield("📊 [Symbol] #{intent_data[:underlying_symbol] || 'Not found'}\n") if block_given?
          Rails.logger.info("[AgentRunner] Intent resolved: #{intent_data[:intent]}, symbol: #{intent_data[:underlying_symbol]}, confidence: #{intent_data[:confidence]}")

          # Step 2-6: Loop until ready
          iteration = 0
          max_iterations = ENV.fetch('AI_AGENT_MAX_ITERATIONS', '15').to_i
          max_iterations = [max_iterations, 5].max # Minimum 5 iterations to ensure data collection

          while iteration < max_iterations && !context.ready_for_analysis?
            iteration += 1

            # Step 2: Decide next step (Rails - deterministic)
            next_tool = next_tool(context)

            if next_tool[:tool] == 'abort'
              yield("⏹️  [Agent] Aborting: #{next_tool[:args][:reason]}\n") if block_given?
              Rails.logger.warn("[AgentRunner] Aborted: #{next_tool[:args][:reason]}")
              return {
                verdict: 'NO_TRADE',
                reason: next_tool[:args][:reason],
                context: context.summary,
                iterations: iteration
              }
            end

            if next_tool[:tool] == 'finalize'
              yield("✅ [Agent] Ready for final analysis\n") if block_given?
              break # Ready for final reasoning
            end

            # Step 3: Call ONE tool
            yield("🔧 [Tool] Calling: #{next_tool[:tool]}\n") if block_given?
            Rails.logger.info("[AgentRunner] Calling tool: #{next_tool[:tool]} with args: #{next_tool[:args]}")

            tool_result = execute_tool({ 'tool' => next_tool[:tool], 'arguments' => next_tool[:args] })

            # Step 4: Adapt / reduce / narrow
            tool_result = adapt_tool_result(context, next_tool[:tool], tool_result)

            # Check for NO_TRADE error
            if tool_result.is_a?(Hash) && tool_result[:error] == 'NO_TRADE'
              yield("⏹️  [Agent] NO_TRADE: #{tool_result[:reason]}\n") if block_given?
              return {
                verdict: 'NO_TRADE',
                reason: tool_result[:reason],
                context: context.summary,
                iterations: iteration
              }
            end

            # Step 5: Store facts (not raw data)
            context.add_observation(next_tool[:tool], next_tool[:args], tool_result)

            # Update context with extracted facts
            update_context_from_result(context, tool_result)

            yield("✅ [Tool] Completed: #{next_tool[:tool]}\n") if block_given?

            # Step 6: Check if ready
            next unless context.ready_for_analysis?

            yield("✅ [Agent] Sufficient data collected\n") if block_given?
            Rails.logger.info("[AgentRunner] Sufficient data collected after #{iteration} iterations")
            break
          end

          if iteration >= max_iterations
            yield("⚠️  [Agent] Reached max iterations (#{max_iterations})\n") if block_given?
            Rails.logger.warn('[AgentRunner] Reached max iterations without sufficient data')
          end

          # Step 7: Final LLM reasoning (compact facts only)
          yield("📝 [Agent] Synthesizing final analysis...\n") if block_given?
          final_analysis = synthesize_analysis(context, stream: stream, &)

          {
            analysis: final_analysis,
            context: context.summary, # Compact summary, not full history
            iterations: iteration,
            verdict: context.ready_for_analysis? ? 'ANALYSIS_COMPLETE' : 'INSUFFICIENT_DATA'
          }
        rescue StandardError => e
          error_msg = "[Agent] Error: #{e.class} - #{e.message}\n"
          yield(error_msg) if block_given?
          Rails.logger.error("[AgentRunner] Error: #{e.class} - #{e.message}")
          Rails.logger.error("[AgentRunner] Backtrace: #{e.backtrace.first(5).join("\n")}")
          {
            verdict: 'ERROR',
            error: e.message,
            context: context&.summary
          }
        end

        private

        def update_context_from_result(context, tool_result)
          # Extract only essential facts
          return unless tool_result.is_a?(Hash)

          context.ltp = tool_result[:ltp] || tool_result['ltp'] if tool_result[:ltp] || tool_result['ltp']
          context.indicators = aggregate_indicators_for_context(tool_result) if tool_result[:indicators] || tool_result['indicators']

          # Update strikes if present (even if empty array, we want to know it was attempted)
          if tool_result.key?(:strikes) || tool_result.key?('strikes')
            strikes = tool_result[:strikes] || tool_result['strikes']
            context.filtered_strikes = filter_strikes_for_context(strikes) if strikes.is_a?(Array)
          end

          context.resolved_instrument = Instrument.find_by(id: tool_result[:instrument_id] || tool_result['instrument_id']) if tool_result[:instrument_id] || tool_result['instrument_id']
        end

        def aggregate_indicators_for_context(tool_result)
          indicators = tool_result[:indicators] || tool_result['indicators'] || {}
          return {} unless indicators.is_a?(Hash)

          aggregated = {}
          indicators.each do |timeframe, tf_indicators|
            aggregated[timeframe] = {}
            tf_indicators.each do |name, value|
              # Preserve error entries
              if name.to_s == 'error'
                aggregated[timeframe][name] = value
                next
              end

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
          return [] unless strikes.is_a?(Array)

          strikes.first(5) # Max 5 strikes
        end

        def synthesize_analysis(context, stream: false, &)
          # Build compact prompt with facts only
          facts_prompt = build_facts_prompt(context)

          model = if @client.provider == :ollama
                    ENV['OLLAMA_MODEL'] || @client.selected_model || 'llama3.1:8b'
                  else
                    'gpt-4o'
                  end

          messages = [
            { role: 'system', content: build_synthesis_system_prompt },
            { role: 'user', content: facts_prompt }
          ]

          if stream && block_given?
            @client.chat_stream(messages: messages, model: model, temperature: 0.3, &)
          else
            @client.chat(messages: messages, model: model, temperature: 0.3)
          end
        end

        def build_facts_prompt(context)
          # Compact facts only - NO raw data
          indicators_text = if context.indicators.any?
                              context.indicators.map do |timeframe, inds|
                                # Handle error entries specially
                                if inds.key?('error') || inds.key?(:error)
                                  error_msg = inds['error'] || inds[:error]
                                  "  #{timeframe}: error: #{error_msg}"
                                else
                                  ind_values = inds.map { |name, val| "#{name}: #{val}" }.join(', ')
                                  "  #{timeframe}: #{ind_values}"
                                end
                              end.join("\n")
                            else
                              '  None'
                            end

          strikes_text = if context.filtered_strikes.any?
                           strikes_list = context.filtered_strikes.map do |strike|
                             strike_val = strike[:strike] || strike['strike'] || strike

                             # Get CE and PE data
                             ce_data = strike[:ce] || strike['ce']
                             pe_data = strike[:pe] || strike['pe']

                             # Build option details
                             option_parts = []

                             if ce_data
                               ce_ltp = ce_data[:ltp] || ce_data['ltp'] || ce_data[:premium] || ce_data['premium']
                               option_parts << if ce_ltp
                                                 "CE:₹#{ce_ltp.to_f.round(2)}"
                                               else
                                                 'CE'
                                               end
                             end

                             if pe_data
                               pe_ltp = pe_data[:ltp] || pe_data['ltp'] || pe_data[:premium] || pe_data['premium']
                               option_parts << if pe_ltp
                                                 "PE:₹#{pe_ltp.to_f.round(2)}"
                                               else
                                                 'PE'
                                               end
                             end

                             # Format: Strike (CE:premium, PE:premium)
                             if option_parts.any?
                               "₹#{strike_val.to_f.round(2)} (#{option_parts.join(', ')})"
                             else
                               "₹#{strike_val.to_f.round(2)}"
                             end
                           end
                           strikes_list.join(', ')
                         else
                           'None'
                         end

          <<~PROMPT
            Analyze based on these facts:

            Instrument: #{context.resolved_instrument&.symbol_name || context.underlying_symbol || 'Unknown'}
            LTP: #{context.ltp || 'Not available'}
            Intent: #{context.intent}
            Timeframe: #{context.timeframe_hint}

            Indicators:
            #{indicators_text}

            #{"Option Strikes (ATM ±1 ±2): #{strikes_text}" if context.intent == :options_buying}

            Provide OPTIONS TRADING analysis and recommendation based on these facts.

            CRITICAL - OPTIONS TRADING FOCUS:
            - You are analyzing for OPTIONS BUYING ONLY (CALL or PUT options), NOT buying the underlying index (NIFTY/SENSEX/BANKNIFTY)
            - CRITICAL: We ONLY BUY options (never write/sell options). This is an OPTIONS BUYING strategy only.
            - NEVER recommend "BUY NIFTY" or "SELL SENSEX" - always recommend "BUY CALL options" or "BUY PUT options"
            - NEVER recommend writing/selling options - we only buy options and exit by closing the long position
            - MANDATORY: You MUST provide specific strike recommendations with exact strike prices
            - If option strikes are provided in the data, use them to recommend specific strikes (e.g., "Buy CALL at strike ₹26,300 (ATM) and ₹26,350 (ATM+1)")
            - If strikes are not provided, calculate ATM strike from LTP and recommend strikes around it (ATM, ATM+1, ATM-1)
            - Consider time decay (theta) and volatility (IV) for intraday options trading
            - Provide entry levels, target strikes, and stop-loss levels for the OPTIONS positions
            - Mention expiry date considerations for intraday trading
            - TERMINOLOGY: Use "EXIT" or "exit the position" when describing exits - NEVER use "sell options" (which implies options selling/writing)
            - Exit levels should reference either premium prices or index spot levels (the underlying index price)
            - Use SL for stop loss, TP1/TP2 for take profit levels

            RECOMMENDATION FORMAT (MANDATORY):
            - "Buy CALL options at strike ₹26,300 (ATM) and ₹26,350 (ATM+1) for bullish move"
            - "Buy PUT options at strike ₹26,250 (ATM-1) and ₹26,200 (ATM-2) for bearish move"
            - ALWAYS include at least 2-3 specific strike prices with their labels (ATM, ATM+1, etc.)
            - Include strike selection reasoning based on technical levels and current LTP
            - NEVER give vague recommendations like "buy options" - always specify exact strikes

            IMPORTANT FORMATTING: Always include spaces between words and numbers.
            Examples: "Buy CALL options at strike ₹26,300" (correct), NOT "buycallat26300" (incorrect).
            Examples: "CALL strikes: ₹26,300 (ATM), ₹26,350 (ATM+1)" (correct).
          PROMPT
        end

        def build_synthesis_system_prompt
          <<~PROMPT
            You are a technical analysis expert specializing in OPTIONS TRADING for Indian index derivatives (NIFTY, BANKNIFTY, SENSEX).

            CRITICAL: You are analyzing for OPTIONS BUYING ONLY, not buying the underlying index.
            - We ONLY BUY options (CALL or PUT) - we NEVER write/sell options
            - This is an OPTIONS BUYING strategy exclusively - no options selling/writing
            Focus on:
            - BUYING CALL options for bullish moves
            - BUYING PUT options for bearish moves
            - Strike selection based on technical levels and risk/reward
            - Exiting by closing the long position (NOT by selling/writing options)

            MANDATORY REQUIREMENTS:
            1. **MUST provide specific strike recommendations** - Never give vague recommendations like "buy options"
            2. **MUST calculate strikes from LTP if not provided** - Use ATM (At The Money) based on current LTP
            3. **MUST include at least 2-3 specific strike prices** with labels (ATM, ATM+1, ATM-1, etc.)
            4. **MUST explain strike selection reasoning** based on technical levels

            Provide a complete trading action plan for options buyers:

            **MANDATORY SECTIONS:**

            1. **Trade Decision** (MANDATORY):
               - State clearly: "BUY CE" or "BUY PE" or "AVOID TRADING"
               - If AVOID: Explain why current technical conditions are not suitable
               - If BUY: Provide specific reasoning based on indicators

            2. **Current Market State** (Brief):
               - Index price and trend (1-2 sentences)

            3. **Technical Analysis**:
               - Analysis using indicators (RSI, MACD, ADX, Supertrend, ATR) - be specific with values
               - Explain what each indicator suggests

            4. **Strike Selection** (MANDATORY if trading):
               - Recommend 2-3 specific strike prices with exact values (e.g., "₹26,300", "₹26,350", "₹26,400")
               - Label each strike (ATM, ATM+1, ATM-1, etc.)
               - If strikes not provided in data, calculate from LTP: Round LTP to nearest 50 (for indices), then recommend ATM, ATM+1, ATM-1
               - Explain why these strikes were chosen based on technical levels (support/resistance, indicator levels)
               - Include premium considerations if available

            5. **Entry Strategy** (MANDATORY if trading):
               - Specific entry price level or trigger condition
               - Entry timing (immediate, wait for pullback, wait for confirmation)
               - How to enter (market order, limit order, specific price level)

            6. **Exit Strategy** (MANDATORY if trading):
               - Stop Loss (SL): Specific premium level or index spot level to EXIT the position
                 * Format: "SL at premium ₹X" or "SL at index spot ₹Y" (specify which)
                 * Calculate index spot level using DELTA if providing spot levels
               - Take Profit (TP): Use TP1, TP2 format for multiple targets
                 * Format: "TP1 at premium ₹X" or "TP1 at index spot ₹Y"
                 * Format: "TP2 at premium ₹X" or "TP2 at index spot ₹Y" (if applicable)
                 * Always provide at least TP1, optionally TP2 for partial exits
               - Index Spot Levels to Watch: Provide key index levels to monitor for exit decisions
                 * Format: "Watch index spot ₹X for TP1", "Watch index spot ₹Y for SL"
                 * These are the underlying index price levels (NIFTY/SENSEX/BANKNIFTY spot prices)
               - Exit timing: When to exit (time-based, price-based, or signal-based)
               - TERMINOLOGY: Always use "EXIT" or "exit the position" - NEVER use "sell options" (we only buy options, never write/sell them)

            7. **Risk Management** (MANDATORY if trading):
               - Position sizing: How much capital to allocate
               - Risk per trade: Maximum loss acceptable
               - Time decay considerations: Expiry date impact for intraday

            FORMATTING:
            - Always include spaces: "at ₹26,300" NOT "at26300"
            - Specify option type: "CALL options" or "PUT options"
            - Include strike prices: "Buy CALL at strike ₹26,300 (ATM) and ₹26,350 (ATM+1)"
            - Use specific numbers, not ranges: "₹26,300" not "around ₹26,300"

            Be concise, actionable, and focused on OPTIONS BUYING ONLY.
            - Do not recommend buying the index itself
            - NEVER recommend options selling/writing - we ONLY buy options
            - TERMINOLOGY: Use "EXIT" or "exit the position" - NEVER "sell options"
            - Exit strategy must include: SL (stop loss), TP1 (take profit 1), optionally TP2 (take profit 2)
            - Reference index spot levels (underlying index price) to watch for exit decisions
            NEVER give vague recommendations - always specify exact strikes.
          PROMPT
        end
      end
    end
  end
end
