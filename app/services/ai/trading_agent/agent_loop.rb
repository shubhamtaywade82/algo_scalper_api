# frozen_string_literal: true

# rubocop:disable-next Style/ArgumentsForwarding, Performance/RedundantBlockCall
module Ai
  module TradingAgent
    # Core orchestration loop for the trading agent.
    # Handles intent resolution, tool dispatching, and LLM synthesis.
    class AgentLoop
      INDEX_SYMBOLS_FOR_FETCH = %w[NIFTY NIFTY50 BANKNIFTY SENSEX].freeze

      attr_accessor :model

      def initialize(model: nil)
        @client = Services::Ai::OllamaClient.instance
        @model = model || ENV['OLLAMA_MODEL'] || 'gpt-oss:20b'
        @max_iterations = ENV.fetch('AI_AGENT_MAX_ITERATIONS', '15').to_i
        @synthesis_timeout = ENV.fetch('AI_AGENT_SYNTHESIS_TIMEOUT', '25').to_i
      end

      # Main agent loop for a specific symbol analysis.
      # Yields chunks for streaming output.
      def run(symbol:, timeframe: '15m', &block)
        trace = TraceLogger.new
        intent = resolve_intent(symbol, timeframe)

        yield("\u{1f50d} [Intent] #{intent[:intent]} (confidence: #{(intent[:confidence] * 100).round}%)\n") if block
        yield("\u{1f4ca} [Symbol] #{symbol} @ #{timeframe}\n") if block

        # Resolve instrument via DhanHQ
        instrument_result = resolve_instrument(symbol)
        if instrument_result[:error]
          trace.log_error(instrument_result[:error])
          yield("\u274c #{instrument_result[:error]}\n") if block
          return { action: 'ERROR', error: instrument_result[:error], trace: trace.to_h }
        end

        instrument_result[:instrument_id]
        trace.log_tool_call('get_instrument', { symbol: symbol })

        # Get market snapshot (LTP + indicators in one call)
        yield("\u{1f4c8} Fetching market data...\n") if block
        snapshot = ToolRegistry.execute('get_market_snapshot', {
          'symbol' => symbol,
          'interval' => map_timeframe(timeframe)
        })
        trace.log_observation('get_market_snapshot', snapshot)

        ltp = snapshot[:ltp]
        yield("\u{1f4b0} LTP: \u20b9#{ltp}\n") if ltp && block

        indicators = snapshot[:indicators]
        yield("\u{1f4ca} Indicators loaded\n") if indicators && block

        # Analyze SMC
        yield("\u{1f3af} Analyzing market structure...\n") if block
        smc = ToolRegistry.execute('get_smc_analysis', { 'symbol' => symbol })
        trace.log_observation('get_smc_analysis', smc)

        # Fetch option chain if options intent
        option_chain = nil
        if intent[:intent] == :options_buying
          yield("\u{1f4ca} Fetching option chain...\n") if block
          option_chain = ToolRegistry.execute('get_option_intelligence', { 'symbol' => symbol })
          trace.log_observation('get_option_intelligence', option_chain)
        end

        # Synthesize analysis
        yield("\u{1f4dd} Synthesizing analysis...\n") if block
        analysis = synthesize(
          symbol: symbol,
          ltp: ltp,
          indicators: indicators,
          smc: smc,
          option_chain: option_chain,
          intent: intent,
          &block
        )

        # Parse trade intent from analysis
        trade_intent = parse_trade_intent(analysis, symbol, ltp)

        # Validate risk
        if trade_intent[:action] && %w[BUY SELL].include?(trade_intent[:action])
          yield("\u{1f6e1}\u{fe0f} Validating risk...\n") if block
          risk_result = RiskValidator.validate(
            trade_intent,
            equity: fetch_equity,
            data_timestamp: Time.current
          )
          trace.log_risk_check(risk_result.risk_checks)

          unless risk_result.approved
            yield("\u26a0\ufe0f Risk rejected: #{risk_result.risk_checks}\n") if block
            trade_intent[:action] = 'HOLD'
            trade_intent[:risk_rejected] = true
          end
        end

        trace.log_intent(trade_intent)

        {
          action: trade_intent[:action],
          confidence: trade_intent[:confidence],
          analysis: analysis,
          trade_intent: trade_intent,
          trace: trace.to_h
        }
      end

      # Run a general query (not symbol-specific).
      def run_query(query:, conversation: [], &block)
        # Pre-fetch fresh data for index options queries
        prefetched = pre_fetch_index_data(query)

        # Build messages from conversation history + new query
        user_content = if prefetched
                         "#{prefetched}\n\n#{query}"
                       else
                         query
                       end

        messages = [
          { role: 'system', content: PromptBuilder.system_prompt }
        ]
        # When pre-fetching, skip old conversation — fresh data is all that matters
        messages.concat(conversation) unless prefetched
        messages << { role: 'user', content: user_content }

        # If we have pre-fetched data, skip tools entirely — model analyzes directly
        if prefetched
          response = @client.chat(
            messages: messages,
            model: @model,
            temperature: 0.3
          )
          content = extract_response_content(response)
          Rails.logger.debug { "[TradingAgent] Pre-fetched response: blank=#{content.blank?} len=#{content.to_s.length}" }
          block.call(content) if content.present? && block
          messages << { role: 'assistant', content: content } if content.present?
          return messages.reject { |m| m[:role] == 'system' }
        end

        # No pre-fetched data — use tool-calling flow
        # Try streaming first
        response = @client.chat_stream(
          messages: messages,
          model: @model,
          temperature: 0.3,
          tools: ToolRegistry.tools_for_ollama,
          &block
        )

        # Extract content from response (handles Ollama::Response objects)
        content = extract_response_content(response)
        Rails.logger.debug { "[TradingAgent] Stream: class=#{response.class} content_blank=#{content.blank?}" }

        # If streaming returned nothing useful, fall back to non-streaming
        if content.blank? && block
          response = @client.chat(
            messages: messages,
            model: @model,
            temperature: 0.3,
            tools: ToolRegistry.tools_for_ollama
          )
          content = extract_response_content(response)
          Rails.logger.debug { "[TradingAgent] Fallback: class=#{response.class} content_blank=#{content.blank?} has_tool_calls=#{response.is_a?(Hash) && response[:tool_calls]&.any?}" }
          block.call(content) if content.present?
        end

        # Normalize response to Hash format
        response = normalize_response(response, tools: ToolRegistry.tools_for_ollama)

        # Handle tool calls in a loop — returns updated messages
        if response.is_a?(Hash) && response[:tool_calls]&.any?
          messages.replace(handle_tool_calls_loop(messages, response, &block))
        end

        # Return updated conversation (exclude system prompt)
        messages.reject { |m| m[:role] == 'system' }

      end

      private

      # Pre-fetch fresh market data for index options queries.
      # Returns a string with current data to inject into the prompt,
      # ensuring the LLM always has fresh data even if it skips tool calls.
      def pre_fetch_index_data(query)
        sym = query.to_s.upcase
        matched = INDEX_SYMBOLS_FOR_FETCH.find { |i| sym.include?(i) }
        return nil unless matched

        symbol_key = case matched
                     when 'NIFTY', 'NIFTY50' then 'NIFTY'
                     when 'BANKNIFTY' then 'BANKNIFTY'
                     when 'SENSEX' then 'SENSEX'
                     else matched
                     end

        instrument = ToolRegistry.execute('get_instrument', { 'symbol' => symbol_key })
        return nil if instrument.is_a?(Hash) && instrument[:error]

        snapshot = ToolRegistry.execute('get_market_snapshot', { 'symbol' => symbol_key, 'interval' => '15' })
        option_intel = ToolRegistry.execute('get_option_intelligence', { 'symbol' => symbol_key })

        parts = ["\n=== USE THESE VALUES EXACTLY — DO NOT USE ANY OTHER DATA ==="]
        parts << "Fetched at #{Time.current.strftime('%H:%M:%S')}"

        if snapshot.is_a?(Hash) && snapshot[:ltp]
          parts << "Underlying LTP: #{snapshot[:ltp]}"
          inds = snapshot[:indicators]
          if inds.is_a?(Hash)
            tf_data = inds.values.first
            if tf_data.is_a?(Hash) && !tf_data.key?('error')
              parts << "Indicators: #{tf_data.map { |k, v| "#{k}=#{v}" }.join(', ')}"
            end
          end
        end

        if option_intel.is_a?(Hash) && option_intel[:atm_strike]
          parts << "ATM Strike: #{option_intel[:atm_strike]}"
          parts << "Lot Size: #{option_intel[:lot_size]}"
          parts << "Expiry: #{option_intel[:selected_expiry]}"
          parts << "Days to Expiry: #{option_intel[:days_to_expiry]}"
          if option_intel[:atm_put]
            atm_pe = option_intel[:atm_put]
            parts << "ATM Put: LTP=#{atm_pe[:ltp]}, Delta=#{atm_pe[:delta]}, Theta=#{atm_pe[:theta]}, IV=#{atm_pe[:iv]}"
          end
          if option_intel[:atm_call]
            atm_ce = option_intel[:atm_call]
            parts << "ATM Call: LTP=#{atm_ce[:ltp]}, Delta=#{atm_ce[:delta]}, Theta=#{atm_ce[:theta]}, IV=#{atm_ce[:iv]}"
          end
          if option_intel[:strikes].is_a?(Array)
            strikes_str = option_intel[:strikes].map do |s|
              ce_ltp = s.dig(:call, :ltp) || s.dig('call', 'ltp')
              pe_ltp = s.dig(:put, :ltp) || s.dig('put', 'ltp')
              "  #{s[:strike]}: CE=#{ce_ltp}, PE=#{pe_ltp}"
            end.join("\n")
            parts << "Strikes:\n#{strikes_str}"
          end
        end

        # Add default position sizing with correct lot_size
        lot_size = option_intel[:lot_size]
        if lot_size && snapshot.is_a?(Hash) && snapshot[:ltp]
          # Default: 1% risk on ₹100k equity
          equity = 100_000.0
          risk_pct = 1.0
          risk_amount = equity * (risk_pct / 100.0)
          # Use ATM put for bearish, ATM call for bullish — use ATM put as default
          entry = option_intel.dig(:atm_put, :ltp) || option_intel.dig(:atm_call, :ltp) || 0
          sl_pct = 0.20 # 20% SL
          sl = entry * (1 - sl_pct)
          risk_per_unit = (entry - sl).abs
          if risk_per_unit.positive?
            raw_qty = (risk_amount / risk_per_unit).floor
            qty = (raw_qty / lot_size) * lot_size
            qty = lot_size if qty.zero?
            parts << "Position Sizing (default 1% risk, ₹#{equity.to_i} equity):"
            parts << "  Lot Size: #{lot_size}"
            parts << "  Entry: ₹#{entry}, SL: ₹#{sl.round(2)} (#{(sl_pct * 100).to_i}% below)"
            parts << "  Quantity: #{qty} contracts (#{qty / lot_size} lots)"
            parts << "  Risk: ₹#{(qty * risk_per_unit).round(2)}"
          end
        end

        parts << '--- END FRESH DATA ---'
        parts.join("\n")
      rescue StandardError => e
        Rails.logger.warn("[TradingAgent] Pre-fetch failed: #{e.message}")
        nil
      end

      # Extracts content from various response formats (Hash, Ollama::Response, String).
      # Handles cloud models that put output in 'thinking' field with empty 'content'.
      def extract_response_content(response)
        return nil if response.nil?

        # Ollama::Response object
        if response.respond_to?(:data)
          msg = response.data&.dig('message') || {}
          content = msg['content'].to_s
          thinking = msg['thinking'].to_s
          return content if content.present?
          return thinking if thinking.present?
          return nil
        end

        # Hash format
        if response.is_a?(Hash)
          content = response[:content] || response['content']
          return content if content.present?

          thinking = response[:thinking] || response['thinking']
          return thinking if thinking.present?
        end

        # String
        response.to_s if response.is_a?(String) && response.present?
      end

      # Convert Ollama::Response to { content:, tool_calls: } Hash
      def normalize_response(response, tools: nil)
        return response if response.is_a?(Hash)
        return response if response.is_a?(String)
        return {} if response.nil?

        # Ollama::Response — extract content and tool_calls
        if response.respond_to?(:data)
          msg = response.data&.dig('message') || {}
          content = msg['content'].to_s.presence
          thinking = msg['thinking'].to_s.presence
          tool_calls = msg['tool_calls'] || []

          # Also check response.message.tool_calls (Ruby Ollama gem format)
          if tool_calls.empty? && response.respond_to?(:message) && response.message.respond_to?(:tool_calls)
            tool_calls = response.message.tool_calls&.map do |tc|
              {
                'id' => tc.id,
                'type' => 'function',
                'function' => {
                  'name' => tc.function&.name,
                  'arguments' => tc.function&.arguments.to_json
                }
              }
            end || []
          end

          { content: content || thinking, tool_calls: tool_calls }
        else
          { content: response.to_s, tool_calls: [] }
        end
      rescue StandardError => e
        Rails.logger.warn("[TradingAgent] normalize_response error: #{e.message}")
        { content: response.to_s, tool_calls: [] }
      end

      def resolve_intent(symbol, timeframe)
        # Determine intent based on symbol and context
        index_symbols = %w[NIFTY BANKNIFTY SENSEX NIFTY50]
        is_index = index_symbols.include?(symbol.upcase)

        intent = if is_index
                   :options_buying
                 else
                   :intraday
                 end

        {
          intent: intent,
          confidence: 0.8,
          underlying_symbol: symbol,
          timeframe_hint: timeframe
        }
      end

      def resolve_instrument(symbol)
        result = ToolRegistry.execute('get_instrument', { 'symbol' => symbol })

        if result.is_a?(Hash) && result[:error].nil?
          {
            instrument_id: result[:security_id],
            exchange_segment: result[:exchange],
            segment: result[:segment]
          }
        else
          { error: result[:error] || "Instrument not found: #{symbol}" }
        end
      end

      def extract_ltp(result)
        return nil unless result.is_a?(Hash)

        data = result['instrument.ltp']
        return nil unless data

        data.is_a?(Hash) ? (data[:ltp] || data['ltp']) : data.to_f
      rescue StandardError
        nil
      end

      def map_timeframe(tf)
        # Map user-friendly timeframe to DhanHQ format
        case tf.to_s.downcase
        when '1m', '1' then '1'
        when '5m', '5' then '5'
        when '15m', '15' then '15'
        when '30m', '30' then '30'
        when '1h', '60m', '60' then '60'
        else '15'
        end
      end

      def fetch_option_chain(symbol, exchange_segment)
        # Get expiries first
        expiries = Ai::DhanToolBridge.call('option.expiries', {
          exchange_segment: exchange_segment,
          symbol: symbol
        })

        return { error: 'Could not fetch expiries' } unless expiries.is_a?(Hash)

        nearest_expiry = extract_nearest_expiry(expiries)
        return { error: 'No expiry found' } unless nearest_expiry

        chain = Ai::DhanToolBridge.call('option.chain', {
          exchange_segment: exchange_segment,
          symbol: symbol,
          expiry: nearest_expiry
        })

        {
          expiry: nearest_expiry,
          chain: chain
        }
      end

      def extract_nearest_expiry(result)
        data = result['option.expiries']
        return nil unless data

        expiries = data.is_a?(Array) ? data : []
        expiries.first
      rescue StandardError
        nil
      end

      def fetch_equity
        result = Ai::DhanToolBridge.call('portfolio.funds')
        return 0 unless result.is_a?(Hash)

        data = result['portfolio.funds']
        return 0 unless data

        (data[:available_cash] || data['available_cash'] || 0).to_f
      rescue StandardError
        0
      end

      def synthesize(symbol:, ltp:, indicators:, smc:, option_chain:, intent:, &block)
        facts = build_facts(symbol: symbol, ltp: ltp, indicators: indicators, smc: smc,
                            option_chain: option_chain, intent: intent)

        messages = [
          { role: 'system', content: PromptBuilder.system_prompt(intent: intent[:intent]) },
          { role: 'user', content: facts }
        ]

        if block
          response = @client.chat_stream(messages: messages, model: @model, temperature: 0.2, &block)
          # Fallback to non-streaming if no content
          content = extract_response_content(response)
          if content.blank?
            response = @client.chat(messages: messages, model: @model, temperature: 0.2)
            content = extract_response_content(response)
            block.call(content) if content.present?
          end
          response
        else
          @client.chat(messages: messages, model: @model, temperature: 0.2)
        end
      end

      def build_facts(symbol:, ltp:, indicators:, smc:, option_chain:, intent:)
        lines = []
        lines << "Symbol: #{symbol}"
        lines << "LTP: #{ltp}" if ltp
        lines << "Intent: #{intent[:intent]}"
        lines << "Timeframe: #{intent[:timeframe_hint]}"
        lines << ''

        # Indicators
        if indicators.is_a?(Hash) && indicators[:indicators]
          lines << 'Indicators:'
          indicators[:indicators].each do |tf, data|
            next if data.is_a?(Hash) && data[:error]

            lines << "  #{tf}: #{format_indicators(data)}"
          end
        end

        # SMC
        if smc.is_a?(Hash) && smc[:timeframes]
          lines << ''
          lines << 'SMC Analysis:'
          smc[:timeframes].each do |tf, data|
            next if data.is_a?(Hash) && data[:error]

            lines << "  #{tf}: trend=#{data[:trend]}, phase=#{data[:phase]}"
          end
          lines << "  Confluence: #{smc[:confluence]}"
        end

        # Option chain
        if option_chain.is_a?(Hash) && option_chain[:chain]
          lines << ''
          lines << "Option Chain (expiry: #{option_chain[:expiry]}):"
          lines << "  Chain data available" if option_chain[:chain]
        end

        lines.join("\n")
      end

      def format_indicators(data)
        return 'N/A' unless data.is_a?(Hash)

        parts = []
        parts << "RSI=#{data[:rsi]&.round(1)}" if data[:rsi]
        parts << "ADX=#{data[:adx]&.round(1)}" if data[:adx]
        parts << "ST=#{data[:supertrend]}" if data[:supertrend]
        parts.join(', ')
      end

      def parse_trade_intent(analysis, symbol, ltp)
        return { action: 'HOLD', confidence: 0 } unless analysis.is_a?(String)

        # Try to extract JSON from the analysis
        json_match = analysis.match(/\{[^{}]*"action"[^{}]*\}/)
        return { action: 'HOLD', confidence: 0 } unless json_match

        parsed = JSON.parse(json_match[0])
        {
          action: parsed['action']&.upcase,
          entry_price: parsed['entry_price']&.to_f || ltp,
          stop_loss: parsed['stop_loss']&.to_f,
          take_profit: parsed['take_profit']&.to_f,
          risk_percent: parsed['risk_percent']&.to_f || 1.0,
          confidence: parsed['confidence']&.to_f || 0.5
        }
      rescue JSON::ParserError
        { action: 'HOLD', confidence: 0 }
      end

      def handle_tool_calls_loop(messages, initial_response, &block)
        # Strip old tool results from conversation — only keep system prompt + recent user/assistant turns
        clean_messages = messages.reject do |m|
          m[:role] == 'user' && m[:content]&.include?('Here is the market data I collected')
        end
        current_messages = clean_messages.dup
        response = initial_response
        all_tool_results = []

        3.times do |iteration|
          # Execute each tool call and collect results
          tool_calls = response.is_a?(Hash) ? (response[:tool_calls] || []) : []
          break if tool_calls.empty?

          tool_calls.each do |tc|
            func_name = tc.dig('function', 'name')
            next unless func_name # skip malformed tool calls

            func_args = begin
                          JSON.parse(tc.dig('function', 'arguments') || '{}')
            rescue JSON::ParserError
                          {}
            end

            yield("\u{1f527} Tool: #{func_name}\n") if block

            result = ToolRegistry.execute(func_name, func_args)
            result_str = truncate_tool_result(result)

            yield(format_tool_result(func_name, result)) if block

            all_tool_results << "[#{func_name}]: #{result_str}"
          end

          # Build a clean single message with all tool results
          tool_summary = all_tool_results.join("\n\n")
          current_messages << {
            role: 'user',
            content: "Here is the FRESH market data I just collected at #{Time.current.strftime('%H:%M:%S')}:\n\n#{tool_summary}\n\n" \
                     'Use ONLY this data (not any previous tool results). Provide your analysis. Trade Decision, Strike Selection with Greeks, Entry, Exit, Risk Management.'
          }

          # On final iteration, remove tools to force text generation
          use_tools = iteration < 2

          # Re-query
          Rails.logger.debug { "[TradingAgent] Re-querying (#{current_messages.size} messages)" }
          response = @client.chat(
            messages: current_messages,
            model: @model,
            temperature: 0.3,
            tools: use_tools ? ToolRegistry.tools_for_ollama : nil
          )
          Rails.logger.debug { "[TradingAgent] Response: class=#{response.class} is_hash=#{response.is_a?(Hash)}" }

          show_thinking(response, &block) if block
          response = normalize_response(response) if response.respond_to?(:data)
        end

        content = extract_response_content(response)
        Rails.logger.debug { "[TradingAgent] Final content: blank=#{content.blank?} len=#{content.to_s.length}" }

        yield(content) if content.present? && block
        current_messages
      end

      # Format a concise tool result for display
      def format_tool_result(name, result)
        return "\n" if result.nil?

        case name
        when 'get_instrument'
                    if result.is_a?(Hash) && result[:display_name]
                      "  \u2192 #{result[:display_name]} (#{result[:security_id]}) [#{result[:exchange]}/#{result[:segment]}]\n"
                    else
                      "  \u2192 #{safe_json(result)}\n"
                    end
        when 'get_market_snapshot'
                    if result.is_a?(Hash) && result[:ltp]
                      indicators = result[:indicators]
                      rsi = indicators[:rsi] if indicators.is_a?(Hash)
                      "  \u2192 LTP: #{result[:ltp]} | RSI: #{rsi&.round(1) || 'N/A'}\n"
                    else
                      "  \u2192 #{safe_json(result)}\n"
                    end
        when 'get_option_intelligence'
                    if result.is_a?(Hash) && result[:atm_strike]
                      days = result[:days_to_expiry]
                      expiry_note = if result[:is_expiry_today]
                                      ' [EXPIRY TODAY!]'
                                    elsif result[:is_expiry_week]
                                      " [#{days}d to expiry]"
                                    else
                                      " [#{days}d]"
                                    end
                      strikes_count = result[:strikes]&.length || 0
                      atm_call = result[:atm_call]
                      atm_put = result[:atm_put]
                      call_str = atm_call ? "C: ₹#{atm_call[:ltp]} Δ#{atm_call[:delta]} Θ#{atm_call[:theta]} IV#{atm_call[:iv]}" : ''
                      put_str = atm_put ? "P: ₹#{atm_put[:ltp]} Δ#{atm_put[:delta]} Θ#{atm_put[:theta]} IV#{atm_put[:iv]}" : ''
                      "  \u2192 ATM: #{result[:atm_strike]}#{expiry_note} | #{strikes_count} strikes | #{call_str} | #{put_str}\n"
                    else
                      "  \u2192 #{safe_json(result)}\n"
                    end
        when 'get_smc_analysis'
                    if result.is_a?(Hash)
                      "  \u2192 Bias: #{result[:bias]} | Confluence: #{result[:confluence]}\n"
                    else
                      "  \u2192 #{safe_json(result)}\n"
                    end
        when 'get_historical_data'
                    count = result.is_a?(Hash) ? (result[:count] || 0) : 0
                    "  \u2192 #{count} candles\n"
        else
                    "  \u2192 #{safe_json(result)}\n"
        end
      rescue StandardError
        "  \u2192 #{safe_json(result)}\n"
      end

      # Safely extract nested tool data from result Hash
      def extract_tool_data(result, key)
        return nil unless result.is_a?(Hash)
        result[key] || result[key.to_sym]
      end

      def safe_json(result)
        result.to_json[0..120]
      rescue StandardError
        result.to_s[0..120]
      end

      # Show thinking content if present in response
      def show_thinking(response, &block)
        return unless response.is_a?(Hash)

        thinking = response[:thinking] || response['thinking']
        return if thinking.blank?

        yield("\n\u{1f9e0} Thinking...\n") if block
        yield("#{thinking}\n\n") if block
      end

      # Truncate tool results to avoid token limits.
      # Summarizes option chains to only ATM strikes.
      def truncate_tool_result(result, max_length: 4000)
        return '{}' if result.nil?

        # Special handling for option.chain — summarize to ATM ± 5 strikes
        if result.is_a?(Hash) && result['option.chain']
          return summarize_option_chain(result['option.chain'])
        end

        json_str = result.to_json
        return json_str if json_str.length <= max_length

        # Truncate and add indicator
        "#{json_str[0...max_length]}...[truncated]"
      end

      def summarize_option_chain(chain)
        last_price = chain['last_price'] || chain[:last_price]
        strikes = chain['strikes'] || chain[:strikes] || []
        return chain.to_json[0..4000] unless last_price && strikes.is_a?(Array) && strikes.any?

        # Filter to strikes within ±5% of ATM
        atm = last_price.round(-2) # Round to nearest 100
        range = (atm * 0.05).round(-2)
        near = strikes.select do |s|
          strike = s['strike'] || s[:strike]
          strike && (strike - atm).abs <= [range, 500].max
        end

        {
          last_price: last_price,
          atm_strike: atm,
          strikes_near_atm: near.length,
          strikes: near.first(10)
        }.to_json
      end
    end
  end
end
