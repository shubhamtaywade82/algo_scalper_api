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
                           context.filtered_strikes.map do |strike|
                             strike_val = strike[:strike] || strike['strike'] || strike
                             "#{strike_val}"
                           end.join(', ')
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

            Provide trading analysis and recommendation based on these facts.
          PROMPT
        end

        def build_synthesis_system_prompt
          <<~PROMPT
            You are a technical analysis expert for Indian markets.

            Based on the provided facts, provide:
            1. Current market state
            2. Technical analysis using the indicators
            3. Trading recommendation (BUY/SELL/HOLD/NO_TRADE)
            4. Risk considerations

            Be concise and actionable. Use only the facts provided - do not make assumptions.
          PROMPT
        end
      end
    end
  end
end
