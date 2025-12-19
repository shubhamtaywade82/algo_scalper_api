# frozen_string_literal: true

require 'timeout'

module Services
  module Ai
    # Technical Analysis Agent with Function Calling
    # Integrates with instruments, DhanHQ, indicators, and trading tools
    class TechnicalAnalysisAgent
      class << self
        def analyze(query:, stream: false, &)
          new.analyze(query: query, stream: stream, &)
        end
      end

      def initialize
        @client = Services::Ai::OpenaiClient.instance
        @tools = build_tools_registry
        @tool_cache = {} # Cache tool results within conversation
        @index_config_cache = nil # Cache index configs
        @analyzer_cache = {} # Cache analyzer instances
        @error_history = [] # Track errors in current conversation for learning
        @learned_patterns = load_learned_patterns # Load learned patterns from storage
      end

      def analyze(query:, stream: false, &)
        return nil unless @client.enabled?

        # Clear caches for new conversation
        @tool_cache = {}
        @index_config_cache = nil
        @analyzer_cache = {}
        @error_history = []
        @current_query_keywords = extract_keywords(query) # Store for error learning

        # Build system prompt with available tools
        system_prompt = build_system_prompt

        # Add current date context to user query
        current_date = Time.zone.today.strftime('%Y-%m-%d')
        enhanced_query = "#{query}\n\nIMPORTANT: Today's date is #{current_date}. Always use current dates (not past dates like 2023)."

        # Add learned patterns to system prompt if available
        if @learned_patterns.any?
          learned_context = build_learned_context
          system_prompt += "\n\n#{learned_context}" if learned_context.present?
        end

        # Initial user query
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user', content: enhanced_query }
        ]

        # Auto-select model (prefer faster models for agent)
        model = if @client.provider == :ollama
                  # For agent, prefer faster models - llama3.1:8b is good balance
                  ENV['OLLAMA_MODEL'] || @client.selected_model || 'llama3.1:8b'
                else
                  'gpt-4o'
                end

        # No max_iterations limit - agent will iterate until it provides a final analysis
        # Safety limits are built into execute_conversation methods

        # Execute conversation with function calling
        if stream && block_given?
          execute_conversation_stream(messages: messages, model: model, &)
        else
          execute_conversation(messages: messages, model: model)
        end
      end

      private

      def build_system_prompt
        <<~PROMPT
          You are an expert technical analysis agent for Indian markets - both indices (NIFTY, BANKNIFTY, SENSEX) and equity stocks (RELIANCE, TCS, INFY, etc.).

          IMPORTANT SEGMENT RULES:
          - Indices (NIFTY, BANKNIFTY, SENSEX) use segment: "index"
          - Stocks/Equities (RELIANCE, TCS, INFY, HDFC, etc.) use segment: "equity"
          - The tools auto-detect segment, but you can explicitly specify if needed

          EFFICIENCY TIP: Use the 'get_comprehensive_analysis' tool to gather ALL data in ONE call (instrument, LTP, historical data, and ALL indicators). This is much faster than making multiple separate tool calls. Only use individual tools if you need specific data that wasn't included in the comprehensive analysis.

          You have access to the following tools:
          #{format_tools_for_prompt}

          When analyzing markets, you can:
          1. Fetch real-time market data (LTP, OHLC) for indices and instruments
          2. Calculate technical indicators: RSI, MACD, ADX, Supertrend, ATR, BollingerBands
          3. Analyze option chains and derivative data
          4. Query historical price data
          5. Get current positions and trading statistics

          IMPORTANT: You have access to MULTIPLE indicators, not just RSI. Use the appropriate indicator for your analysis:

          INDICATOR INTERPRETATION GUIDE (CRITICAL - READ CAREFULLY):

          **RSI (Relative Strength Index) - 0 to 100 scale:**
          - RSI < 30 = OVERSOLD (potential buying opportunity, but not a guarantee)
          - RSI 30-50 = NEUTRAL/BEARISH (no clear signal)
          - RSI 50-70 = NEUTRAL/BULLISH (no clear signal)
          - RSI > 70 = OVERBOUGHT (potential selling opportunity, but not a guarantee)
          - RSI around 50 = NEUTRAL (no strong momentum in either direction)
          - NEVER say "slightly oversold" for RSI values between 40-60 - these are NEUTRAL

          **MACD (Moving Average Convergence Divergence):**
          - Positive MACD + Positive Histogram = BULLISH momentum
          - Negative MACD + Negative Histogram = BEARISH momentum
          - MACD above Signal = BULLISH crossover (potential buy signal)
          - MACD below Signal = BEARISH crossover (potential sell signal)
          - Histogram positive and increasing = Strengthening bullish momentum
          - Histogram negative and decreasing = Strengthening bearish momentum

          **ADX (Average Directional Index) - 0 to 100 scale:**
          - ADX < 20 = WEAK TREND (ranging/consolidation market)
          - ADX 20-40 = MODERATE TREND STRENGTH
          - ADX > 40 = STRONG TREND (trending market)
          - ADX > 50 = VERY STRONG TREND
          - ADX does NOT indicate direction (bullish/bearish), only TREND STRENGTH
          - High ADX (>40) means trend is strong, but you need other indicators to determine direction

          **Supertrend:**
          - Returns "long_entry" = BULLISH signal (price above trend line, potential buy)
          - Returns "short_entry" = BEARISH signal (price below trend line, potential sell)
          - "short_entry" does NOT mean "bounce opportunity" - it means BEARISH/DOWNWARD trend
          - "long_entry" means BULLISH/UPWARD trend

          **ATR (Average True Range):**
          - Measures VOLATILITY, not direction
          - Higher ATR = Higher volatility (larger price swings)
          - Lower ATR = Lower volatility (smaller price swings)
          - Use ATR to assess risk and position sizing, not for entry/exit signals

          **Bollinger Bands:**
          - Price near UPPER band = Potentially overbought (but not a sell signal alone)
          - Price near LOWER band = Potentially oversold (but not a buy signal alone)
          - Price between bands = Normal trading range
          - Bands widening = Increasing volatility
          - Bands narrowing = Decreasing volatility (potential breakout coming)

          ANALYSIS RULES:
          1. Always use MULTIPLE indicators together - never rely on a single indicator
          2. Look for CONFLUENCE - when multiple indicators agree, the signal is stronger
          3. Consider TREND CONTEXT - is the overall trend bullish or bearish?
          4. ADX tells you TREND STRENGTH, not direction - combine with Supertrend/MACD for direction
          5. RSI values between 40-60 are NEUTRAL - don't call them "oversold" or "overbought"
          6. Supertrend "short_entry" = BEARISH, not "bounce opportunity"
          7. When indicators conflict, acknowledge the conflict and explain which is stronger

          Use the available tools to gather data before providing analysis.
          When you receive indicator data with "indicator_interpretations", use those interpretations to guide your analysis.
          The interpretations are pre-calculated to help you understand what each indicator value means.

          Provide actionable, data-driven insights based on the tools you use.
          Always cross-reference multiple indicators - when they agree, the signal is stronger.
          When indicators conflict, explain the conflict and which signal is stronger based on trend context.

          When you need to use a tool, respond with ONLY the JSON tool call (no explanations, no markdown):
          {
            "tool": "tool_name",
            "arguments": {
              "param1": "value1",
              "param2": "value2"
            }
          }

          CRITICAL RULES:
          1. You MUST actually call tools - do NOT just describe what you would do
          2. When calling a tool, respond with ONLY the JSON tool call, nothing else
          3. After receiving tool results, you MUST provide your analysis in natural language
          4. When you have gathered enough data, provide a complete analysis - do NOT call more tools
          5. Your final response should be a clear, actionable analysis based on the tool results
          6. Use CURRENT dates (today is #{Time.zone.today.strftime('%Y-%m-%d')}) - never use old dates like 2023
          7. Be efficient - try to get all needed data in 1-2 tool calls, then provide analysis
        PROMPT
      end

      def format_tools_for_prompt
        @tools.map do |tool_name, tool_def|
          params = tool_def[:parameters].map { |p| "  - #{p[:name]} (#{p[:type]}): #{p[:description]}" }.join("\n")
          <<~TOOL
            **#{tool_name}**
            #{tool_def[:description]}
            Parameters:
            #{params}
          TOOL
        end.join("\n\n")
      end

      def build_tools_registry
        {
          'get_comprehensive_analysis' => {
            description: 'Get comprehensive analysis data for an index or stock in ONE call: finds instrument, fetches LTP, historical data (up to 200 candles), and calculates ALL available indicators (RSI, MACD, ADX, Supertrend, ATR, BollingerBands). Use this instead of multiple separate tool calls for efficiency. IMPORTANT: Use correct segment - indices (NIFTY, BANKNIFTY, SENSEX) use "index", stocks (RELIANCE, TCS, etc.) use "equity".',
            parameters: [
              { name: 'underlying_symbol', type: 'string',
                description: 'Underlying symbol. For indices: "NIFTY", "BANKNIFTY", "SENSEX". For stocks: "RELIANCE", "TCS", "INFY", etc. Auto-detects exchange: SENSEX→BSE, NIFTY/BANKNIFTY→NSE' },
              { name: 'exchange', type: 'string',
                description: 'Exchange: "NSE" or "BSE". Optional - auto-detected from underlying_symbol if not provided (NIFTY/BANKNIFTY→NSE, SENSEX→BSE, others→NSE)' },
              { name: 'segment', type: 'string',
                description: 'Segment: "index" for indices (NIFTY, BANKNIFTY, SENSEX), "equity" for stocks (RELIANCE, TCS, etc.), "derivatives" for futures/options. Default: Auto-detected (if symbol is known index, uses "index", otherwise tries "equity")' },
              { name: 'interval', type: 'string',
                description: 'Timeframe for historical data: 1, 5, 15, 30, 60 (minutes). Default: 5' },
              { name: 'max_candles', type: 'integer',
                description: 'Maximum number of candles to fetch (default: 200, max: 200)' }
            ],
            handler: method(:tool_get_comprehensive_analysis)
          },
          'get_index_ltp' => {
            description: 'Get Last Traded Price (LTP) for an index (NIFTY, BANKNIFTY, SENSEX)',
            parameters: [
              { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' }
            ],
            handler: method(:tool_get_index_ltp)
          },
          'get_instrument_ltp' => {
            description: 'Get LTP for a specific instrument. IMPORTANT: Use correct segment - indices (NIFTY, BANKNIFTY, SENSEX) use "index", stocks/equities (RELIANCE, TCS, INFY) use "equity". For indices, use correct exchange - NIFTY and BANKNIFTY are on NSE, SENSEX is on BSE.',
            parameters: [
              { name: 'underlying_symbol', type: 'string',
                description: 'Underlying symbol. For indices: "NIFTY", "BANKNIFTY", "SENSEX". For stocks: "RELIANCE", "TCS", "INFY", etc.' },
              { name: 'exchange', type: 'string',
                description: 'Exchange: "NSE" or "BSE". IMPORTANT: NIFTY and BANKNIFTY use "NSE", SENSEX uses "BSE". For stocks, typically "NSE". Default: Auto-detected from underlying_symbol (NIFTY/BANKNIFTY=NSE, SENSEX=BSE, others=NSE)' },
              { name: 'segment', type: 'string',
                description: 'Segment: "index" for indices (NIFTY, BANKNIFTY, SENSEX), "equity" for stocks (RELIANCE, TCS, etc.), "derivatives" for futures/options. Default: Auto-detected (if symbol is known index, uses "index", otherwise tries "equity")' }
            ],
            handler: method(:tool_get_instrument_ltp)
          },
          'get_ohlc' => {
            description: 'Get OHLC (Open, High, Low, Close) data for an instrument. IMPORTANT: Use correct segment - indices (NIFTY, BANKNIFTY, SENSEX) use "index", stocks/equities (RELIANCE, TCS, INFY) use "equity". For indices, use correct exchange - NIFTY and BANKNIFTY are on NSE, SENSEX is on BSE.',
            parameters: [
              { name: 'underlying_symbol', type: 'string',
                description: 'Underlying symbol. For indices: "NIFTY", "BANKNIFTY", "SENSEX". For stocks: "RELIANCE", "TCS", "INFY", etc.' },
              { name: 'exchange', type: 'string',
                description: 'Exchange: "NSE" or "BSE". IMPORTANT: NIFTY and BANKNIFTY use "NSE", SENSEX uses "BSE". For stocks, typically "NSE". Default: Auto-detected from underlying_symbol (NIFTY/BANKNIFTY=NSE, SENSEX=BSE, others=NSE)' },
              { name: 'segment', type: 'string',
                description: 'Segment: "index" for indices (NIFTY, BANKNIFTY, SENSEX), "equity" for stocks (RELIANCE, TCS, etc.), "derivatives" for futures/options. Default: Auto-detected (if symbol is known index, uses "index", otherwise tries "equity")' }
            ],
            handler: method(:tool_get_ohlc)
          },
          'calculate_indicator' => {
            description: 'Calculate a technical indicator for an index. Available indicators: RSI (momentum), MACD (trend/momentum), ADX (trend strength), Supertrend (trend direction), ATR (volatility), BollingerBands (volatility/price extremes). Use multiple indicators for comprehensive analysis.',
            parameters: [
              { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' },
              { name: 'indicator', type: 'string',
                description: 'Indicator name: RSI, MACD, ADX, Supertrend, ATR, BollingerBands (or BB). Use the indicator most appropriate for your analysis - don\'t limit to RSI!' },
              { name: 'period', type: 'integer',
                description: 'Period for the indicator (optional, defaults: RSI=14, MACD=12/26/9, ADX=14, Supertrend=7, ATR=14, BollingerBands=20)' },
              { name: 'interval', type: 'string', description: 'Timeframe: 1, 5, 15, 30, 60 (minutes). Default: 1' },
              { name: 'multiplier', type: 'number', description: 'Multiplier for Supertrend (optional, default: 3.0)' },
              { name: 'std_dev', type: 'number',
                description: 'Standard deviation for BollingerBands (optional, default: 2.0)' }
            ],
            handler: method(:tool_calculate_indicator)
          },
          'get_historical_data' => {
            description: 'Get historical OHLC candle data for an index or instrument. IMPORTANT: Use correct segment - indices (NIFTY, BANKNIFTY, SENSEX) use "index", stocks/equities (RELIANCE, TCS, INFY) use "equity". For indices, use correct exchange - NIFTY and BANKNIFTY are on NSE, SENSEX is on BSE.',
            parameters: [
              { name: 'underlying_symbol', type: 'string',
                description: 'Underlying symbol. For indices: "NIFTY", "BANKNIFTY", "SENSEX". For stocks: "RELIANCE", "TCS", "INFY", etc.' },
              { name: 'exchange', type: 'string',
                description: 'Exchange: "NSE" or "BSE". IMPORTANT: NIFTY and BANKNIFTY use "NSE", SENSEX uses "BSE". For stocks, typically "NSE". Default: Auto-detected from underlying_symbol (NIFTY/BANKNIFTY=NSE, SENSEX=BSE, others=NSE)' },
              { name: 'segment', type: 'string',
                description: 'Segment: "index" for indices (NIFTY, BANKNIFTY, SENSEX), "equity" for stocks (RELIANCE, TCS, etc.), "derivatives" for futures/options. Default: Auto-detected (if symbol is known index, uses "index", otherwise tries "equity")' },
              { name: 'interval', type: 'string',
                description: 'Timeframe: 1, 5, 15, 25, 60 (minutes). Default: 5' },
              { name: 'from_date', type: 'string',
                description: 'Start date (YYYY-MM-DD). Default: 3 days before to_date. IMPORTANT: Must be at least 1 day before to_date' },
              { name: 'to_date', type: 'string',
                description: 'End date (YYYY-MM-DD). Default: today. If from_date is same or later, it will be auto-adjusted to 1 day before to_date' }
            ],
            handler: method(:tool_get_historical_data)
          },
          'analyze_option_chain' => {
            description: 'Analyze option chain for an index and get best candidates',
            parameters: [
              { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' },
              { name: 'direction', type: 'string', description: 'bullish or bearish' },
              { name: 'limit', type: 'integer', description: 'Number of candidates to return (default: 5)' }
            ],
            handler: method(:tool_analyze_option_chain)
          },
          'get_trading_stats' => {
            description: 'Get current trading statistics (win rate, PnL, positions)',
            parameters: [
              { name: 'date', type: 'string', description: 'Date in YYYY-MM-DD format (optional, defaults to today)' }
            ],
            handler: method(:tool_get_trading_stats)
          },
          'get_active_positions' => {
            description: 'Get currently active trading positions',
            parameters: [],
            handler: method(:tool_get_active_positions)
          },
          'calculate_advanced_indicator' => {
            description: 'Calculate advanced indicators (HolyGrail, TrendDuration) for an index',
            parameters: [
              { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' },
              { name: 'indicator', type: 'string',
                description: 'Advanced indicator name: HolyGrail, TrendDuration' },
              { name: 'interval', type: 'string',
                description: 'Timeframe: 1, 5, 15, 25, 60 (minutes). Default: 5' },
              { name: 'config', type: 'object', description: 'Optional configuration parameters (JSON object)' }
            ],
            handler: method(:tool_calculate_advanced_indicator)
          },
          'run_backtest' => {
            description: 'Run a backtest on historical data for an index',
            parameters: [
              { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' },
              { name: 'interval', type: 'string',
                description: 'Timeframe: 1, 5, 15, 25, 60 (minutes). Default: 5' },
              { name: 'days_back', type: 'integer', description: 'Number of days to backtest (default: 90)' },
              { name: 'supertrend_cfg', type: 'object',
                description: 'Supertrend configuration: { period: 7, multiplier: 3.0 } (optional)' },
              { name: 'adx_min_strength', type: 'number',
                description: 'Minimum ADX strength threshold (optional, default: 0)' }
            ],
            handler: method(:tool_run_backtest)
          },
          'optimize_indicator' => {
            description: 'Optimize indicator parameters for an index using historical data',
            parameters: [
              { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' },
              { name: 'interval', type: 'string',
                description: 'Timeframe: 1, 5, 15, 25, 60 (minutes). Default: 5' },
              { name: 'lookback_days', type: 'integer',
                description: 'Number of days to use for optimization (default: 45)' },
              { name: 'test_mode', type: 'boolean',
                description: 'Use reduced parameter space for faster testing (default: false)' }
            ],
            handler: method(:tool_optimize_indicator)
          }
        }
      end

      def execute_conversation(messages:, model:)
        # Iterate until we get a final analysis, with configurable safety limits
        # Default: 15 iterations (allows for multiple tool calls and comprehensive analysis)
        # Can be overridden via AI_AGENT_MAX_ITERATIONS environment variable
        safety_limit = ENV.fetch('AI_AGENT_MAX_ITERATIONS', '15').to_i
        safety_limit = [safety_limit, 3].max # Minimum 3 iterations
        safety_limit = [safety_limit, 100].min # Maximum 100 iterations (safety cap)

        iteration = 0
        full_response = ''
        consecutive_tool_calls = 0
        max_consecutive_tools = ENV.fetch('AI_AGENT_MAX_CONSECUTIVE_TOOLS', '8').to_i
        max_consecutive_tools = [max_consecutive_tools, 3].max # Minimum 3
        max_consecutive_tools = [max_consecutive_tools, 15].min # Maximum 15

        Rails.logger.debug { "[TechnicalAnalysisAgent] Starting conversation (safety_limit: #{safety_limit} iterations, max_consecutive_tools: #{max_consecutive_tools})" }

        while iteration < safety_limit
          Rails.logger.debug { "[TechnicalAnalysisAgent] Iteration #{iteration + 1}/#{safety_limit}" }

          response = @client.chat(
            messages: messages,
            model: model,
            temperature: 0.3
          )

          unless response
            Rails.logger.error('[TechnicalAnalysisAgent] No response from AI client')
            return nil
          end

          Rails.logger.debug { "[TechnicalAnalysisAgent] Received response (#{response.length} chars)" }

          # Check if response contains tool call
          tool_call = extract_tool_call(response)
          if tool_call
            consecutive_tool_calls += 1

            # Safety check: if we've called tools 10 times in a row without analysis, force a break
            if consecutive_tool_calls >= max_consecutive_tools
              Rails.logger.warn("[TechnicalAnalysisAgent] Too many consecutive tool calls (#{consecutive_tool_calls}), forcing analysis request")
              messages << { role: 'assistant', content: response }
              messages << {
                role: 'user',
                content: 'You have called many tools. Please provide your analysis now based on all the data you have gathered. ' \
                         'Do not call any more tools - provide a complete analysis with your findings and actionable insights.'
              }
              consecutive_tool_calls = 0 # Reset counter
              iteration += 1
              next
            end

            Rails.logger.debug { "[TechnicalAnalysisAgent] Tool call: #{tool_call['tool']} (consecutive: #{consecutive_tool_calls})" }

            # Execute tool
            tool_result = execute_tool(tool_call)

            # Record errors for learning
            if tool_result.is_a?(Hash) && tool_result[:error]
              record_error(
                tool_name: tool_call['tool'],
                error_message: tool_result[:error],
                query_keywords: @current_query_keywords || []
              )
            end

            # Add assistant message and tool result to conversation
            messages << { role: 'assistant', content: response }
            messages << {
              role: 'tool',
              content: "Tool: #{tool_call['tool']}\nResult: #{JSON.pretty_generate(tool_result)}"
            }
            # Explicitly prompt for analysis after tool result
            messages << {
              role: 'user',
              content: 'Based on the tool result above, provide your analysis. ' \
                       'If you have enough data, provide a complete analysis now. ' \
                       'If you need more data, call another tool.'
            }

            # Keep only last 10 messages (system + recent conversation)
            messages = [messages.first] + messages.last(11) if messages.size > 12 # system + 10 messages

            iteration += 1
            next
          end

          # No tool call - check if response is meaningful
          # Reset consecutive tool calls counter when we get a non-tool response
          consecutive_tool_calls = 0

          if response.strip.length > 20 && !response.match?(/\{"tool"/i)
            # Final response received (has content and no tool call)
            Rails.logger.info('[TechnicalAnalysisAgent] Analysis complete - final response received')
            full_response = response
            break
          else
            # Empty or very short response - prompt for analysis
            Rails.logger.warn("[TechnicalAnalysisAgent] Received very short response (#{response.length} chars), prompting for analysis...")
            messages << { role: 'assistant', content: response }
            messages << {
              role: 'user',
              content: 'Please provide a complete analysis based on the data you have gathered. ' \
                       'Summarize your findings and provide actionable insights. ' \
                       'Do not call more tools - provide your analysis now.'
            }
            iteration += 1
            next
          end
        end

        if iteration >= safety_limit
          Rails.logger.warn("[TechnicalAnalysisAgent] Reached safety limit (#{safety_limit} iterations)")
        end

        Rails.logger.info("[TechnicalAnalysisAgent] Completed in #{iteration} iteration(s)")

        # Save learned patterns at end of conversation
        save_learned_patterns if @error_history.any?

        {
          analysis: full_response,
          generated_at: Time.current,
          provider: @client.provider,
          iterations: iteration,
          errors_encountered: @error_history.size,
          learned_patterns_applied: @learned_patterns.select do |p|
            keywords = p[:keywords] || []
            keywords.any? do |kw|
              @current_query_keywords&.include?(kw)
            end
          end.size
        }
      rescue StandardError => e
        Rails.logger.error("[TechnicalAnalysisAgent] Error: #{e.class} - #{e.message}")
        Rails.logger.error("[TechnicalAnalysisAgent] Backtrace: #{e.backtrace.first(5).join("\n")}")
        nil
      end

      def execute_conversation_stream(messages:, model:, &_block)
        # Iterate until we get a final analysis, with configurable safety limits
        # Default: 15 iterations (allows for multiple tool calls and comprehensive analysis)
        # Can be overridden via AI_AGENT_MAX_ITERATIONS environment variable
        safety_limit = ENV.fetch('AI_AGENT_MAX_ITERATIONS', '15').to_i
        safety_limit = [safety_limit, 3].max # Minimum 3 iterations
        safety_limit = [safety_limit, 100].min # Maximum 100 iterations (safety cap)

        iteration = 0
        full_response = +''
        consecutive_tool_calls = 0
        max_consecutive_tools = ENV.fetch('AI_AGENT_MAX_CONSECUTIVE_TOOLS', '8').to_i
        max_consecutive_tools = [max_consecutive_tools, 3].max # Minimum 3
        max_consecutive_tools = [max_consecutive_tools, 15].min # Maximum 15

        # Stream: Start message
        yield("🔍 [Agent] Starting analysis (safety_limit: #{safety_limit} iterations, max_consecutive_tools: #{max_consecutive_tools})\n\n") if block_given?
        Rails.logger.info("[TechnicalAnalysisAgent] Starting analysis (streaming, safety_limit: #{safety_limit} iterations, max_consecutive_tools: #{max_consecutive_tools})")

        while iteration < safety_limit
          # Stream: Iteration start
          yield("📊 [Agent] Iteration #{iteration + 1}/#{safety_limit}\n") if block_given?
          Rails.logger.info("[TechnicalAnalysisAgent] Iteration #{iteration + 1}/#{safety_limit}")

          response_chunks = +''
          chunk_count = 0

          # Stream: AI thinking indicator
          yield("🤔 [AI] Thinking...\n") if block_given?
          $stdout.flush if block_given?

          begin
            # Use streaming (logs only at completion, not during chunks)
            stream_start = Time.current
            @client.chat_stream(
              messages: messages,
              model: model,
              temperature: 0.3
            ) do |chunk|
              if chunk
                response_chunks << chunk
                chunk_count += 1
                yield(chunk) if block_given?
                $stdout.flush if block_given? # Ensure immediate output
              end
            end

            elapsed = Time.current - stream_start
            Rails.logger.debug { "[TechnicalAnalysisAgent] Stream completed in #{elapsed.round(2)}s (#{chunk_count} chunks, #{response_chunks.length} chars)" }
          rescue Faraday::TimeoutError, Net::ReadTimeout => e
            elapsed = Time.current - stream_start
            Rails.logger.warn("[TechnicalAnalysisAgent] Stream timeout after #{elapsed.round(2)}s: #{e.class} - #{e.message}")
            yield("\n⚠️  [Agent] Stream timeout after #{elapsed.round(2)}s: #{e.message}\n") if block_given?
          rescue StandardError => e
            elapsed = begin
              Time.current - stream_start
            rescue StandardError
              0
            end
            Rails.logger.error("[TechnicalAnalysisAgent] Stream error after #{elapsed.round(2)}s: #{e.class} - #{e.message}")
            Rails.logger.error("[TechnicalAnalysisAgent] Backtrace: #{e.backtrace.first(3).join("\n")}")
            yield("\n❌ [Agent] Stream error: #{e.message}\n") if block_given?
          end

          response = response_chunks
          full_response << response

          # Check if we got any response
          if response.blank? || response.strip.empty?
            yield("\n⚠️  [Agent] No response received from AI, retrying...\n") if block_given?
            Rails.logger.warn('[TechnicalAnalysisAgent] No response received, retrying iteration')
            iteration += 1
            next
          end

          # Stream: Response received
          yield("\n\n✅ [Agent] Response received (#{response.length} chars, #{chunk_count} chunks)\n") if block_given?

          # Check if response contains tool call
          tool_call = extract_tool_call(response)
          if tool_call
            consecutive_tool_calls += 1

            # Safety check: if we've called tools 10 times in a row without analysis, force a break
            if consecutive_tool_calls >= max_consecutive_tools
              yield("⚠️  [Agent] Too many consecutive tool calls (#{consecutive_tool_calls}), forcing analysis request...\n") if block_given?
              Rails.logger.warn("[TechnicalAnalysisAgent] Too many consecutive tool calls (#{consecutive_tool_calls}), forcing analysis request")
              messages << { role: 'assistant', content: response }
              messages << {
                role: 'user',
                content: 'You have called many tools. Please provide your analysis now based on all the data you have gathered. ' \
                         'Do not call any more tools - provide a complete analysis with your findings and actionable insights.'
              }
              consecutive_tool_calls = 0 # Reset counter
              iteration += 1
              next
            end

            # Stream: Tool call detected
            yield("🔧 [Agent] Tool call detected: #{tool_call['tool']} (consecutive: #{consecutive_tool_calls})\n") if block_given?
            Rails.logger.info("[TechnicalAnalysisAgent] Executing tool: #{tool_call['tool']} (consecutive: #{consecutive_tool_calls})")

            # Stream: Tool execution start
            yield("⚙️  [Tool] Executing: #{tool_call['tool']}...\n") if block_given?

            # Execute tool
            tool_result = execute_tool(tool_call)

            # Record errors for learning
            if tool_result.is_a?(Hash) && tool_result[:error]
              record_error(
                tool_name: tool_call['tool'],
                error_message: tool_result[:error],
                query_keywords: @current_query_keywords || []
              )
            end

            # Stream: Tool result
            yield("✅ [Tool] Completed: #{tool_call['tool']}\n") if block_given?
            yield("📋 [Tool] Result:\n#{JSON.pretty_generate(tool_result)}\n\n") if block_given?

            Rails.logger.info("[TechnicalAnalysisAgent] Tool completed: #{tool_call['tool']}")

            # Add assistant message and tool result to conversation
            messages << { role: 'assistant', content: response }
            messages << {
              role: 'user',
              content: "Tool result received. Now provide your analysis based on the data you've gathered. " \
                       'If you have all the information you need, provide a complete analysis. ' \
                       'If you need more data, call another tool.'
            }
            messages << {
              role: 'tool',
              content: "Tool: #{tool_call['tool']}\nResult: #{JSON.pretty_generate(tool_result)}"
            }

            # Stream: Prompting for analysis
            yield("💭 [Agent] Prompting AI for analysis based on tool results...\n\n") if block_given?

            # Keep only last 10 messages (system + recent conversation)
            messages = [messages.first] + messages.last(11) if messages.size > 12 # system + 10 messages

            iteration += 1
            next
          end

          # No tool call - check if response is meaningful
          # Reset consecutive tool calls counter when we get a non-tool response
          consecutive_tool_calls = 0

          if response.strip.length > 20 && !response.match?(/\{"tool"/i)
            # Final response received (has content and no tool call)
            yield("\n✅ [Agent] Analysis complete - final response received!\n") if block_given?
            Rails.logger.info('[TechnicalAnalysisAgent] Analysis complete - final response received')
            break
          else
            # Empty or very short response - prompt for analysis
            yield("⚠️  [Agent] Short response received (#{response.length} chars), prompting for analysis...\n") if block_given?
            Rails.logger.warn("[TechnicalAnalysisAgent] Received very short response (#{response.length} chars), prompting for analysis...")
            messages << { role: 'assistant', content: response }
            messages << {
              role: 'user',
              content: 'Please provide a complete analysis based on the data you have gathered. ' \
                       'Summarize your findings and provide actionable insights. ' \
                       'Do not call more tools - provide your analysis now.'
            }
            iteration += 1
            next
          end
        end

        if iteration >= safety_limit
          yield("\n⚠️  [Agent] Reached safety limit (#{safety_limit} iterations)\n") if block_given?
          Rails.logger.warn("[TechnicalAnalysisAgent] Reached safety limit (#{safety_limit} iterations)")
        end

        yield("\n🏁 [Agent] Completed in #{iteration} iteration(s)\n") if block_given?
        Rails.logger.info("[TechnicalAnalysisAgent] Completed in #{iteration} iteration(s)")

        # Save learned patterns at end of conversation
        save_learned_patterns if @error_history.any?

        {
          analysis: full_response,
          generated_at: Time.current,
          provider: @client.provider,
          iterations: iteration,
          errors_encountered: @error_history.size,
          learned_patterns_applied: @learned_patterns.select do |p|
            keywords = p[:keywords] || []
            keywords.any? do |kw|
              @current_query_keywords&.include?(kw)
            end
          end.size
        }
      rescue StandardError => e
        error_msg = "[Agent] Error: #{e.class} - #{e.message}\n"
        yield(error_msg) if block_given?
        Rails.logger.error("[TechnicalAnalysisAgent] Stream error: #{e.class} - #{e.message}")
        Rails.logger.error("[TechnicalAnalysisAgent] Backtrace: #{e.backtrace.first(5).join("\n")}")
        nil
      end

      def extract_tool_call(response)
        # Try multiple patterns to extract tool call JSON
        # Pattern 1: Direct JSON object
        json_match = response.match(/\{"tool"\s*:\s*"([^"]+)"\s*,\s*"arguments"\s*:\s*(\{.*?\})\s*\}/m)

        # Pattern 2: JSON in code blocks (```json ... ```)
        json_match ||= response.match(/```(?:json)?\s*\{[\s\n]*"tool"[\s\n]*:[\s\n]*"([^"]+)"[\s\n]*,[\s\n]*"arguments"[\s\n]*:[\s\n]*(\{.*?\})[\s\n]*\}[\s\n]*```/m)

        # Pattern 3: JSON after "tool": or similar markers
        json_match ||= response.match(/"tool"\s*:\s*"([^"]+)"\s*,\s*"arguments"\s*:\s*(\{.*?\})/m)

        return nil unless json_match

        begin
          {
            'tool' => json_match[1],
            'arguments' => JSON.parse(json_match[2])
          }
        rescue JSON::ParserError => e
          Rails.logger.debug { "[TechnicalAnalysisAgent] JSON parse error: #{e.message}" }
          Rails.logger.debug { "[TechnicalAnalysisAgent] Attempted to parse: #{json_match[2][0..200]}" }
          nil
        end
      end

      def execute_tool(tool_call)
        tool_name = tool_call['tool']
        arguments = tool_call['arguments'] || {}

        tool_def = @tools[tool_name]
        return { error: "Unknown tool: #{tool_name}" } unless tool_def

        # Check cache for identical tool calls (within same conversation)
        cache_key = "#{tool_name}:#{arguments.sort.to_json}"
        return @tool_cache[cache_key] if @tool_cache[cache_key]

        begin
          result = tool_def[:handler].call(arguments)
          # Cache successful results (not errors) for reuse
          @tool_cache[cache_key] = result unless result.is_a?(Hash) && result[:error]
          result
        rescue StandardError => e
          Rails.logger.error("[TechnicalAnalysisAgent] Tool error (#{tool_name}): #{e.class} - #{e.message}")
          error_result = { error: "#{e.class}: #{e.message}" }

          # Record error for learning (if we have query context)
          if @current_query_keywords
            record_error(
              tool_name: tool_name,
              error_message: e.message,
              query_keywords: @current_query_keywords
            )
          end

          error_result
        end
      end

      # Learning and adaptation methods
      def calculate_max_iterations(query)
        base_iterations = 3
        complexity_score = 0

        # Analyze query complexity
        complexity_score += 1 if query.match?(/\b(and|or|compare|analyze|multiple)\b/i)
        complexity_score += 1 if query.match?(/\b(historical|backtest|optimize)\b/i)
        complexity_score += 1 if query.scan(/\b(NIFTY|BANKNIFTY|SENSEX)\b/i).length > 1

        # Check learned patterns for this query type
        query_keywords = extract_keywords(query)
        learned_complexity = @learned_patterns.select do |pattern|
          pattern[:keywords].any? { |kw| query_keywords.include?(kw) }
        end

        if learned_complexity.any?
          # Increase iterations if we've seen errors with similar queries
          avg_errors = learned_complexity.map { |p| p[:error_count] || 0 }.sum.to_f / learned_complexity.size
          complexity_score += [avg_errors.to_i, 2].min # Cap at +2
        end

        # Dynamic max_iterations: base + complexity (min 3, max 8)
        [base_iterations + complexity_score, 8].min
      end

      def extract_keywords(query)
        # Extract meaningful keywords from query
        query.downcase
             .gsub(/[^\w\s]/, ' ')
             .split(/\s+/)
             .reject { |w| w.length < 3 || %w[the is are was were what how when where].include?(w) }
             .uniq
             .first(10)
      end

      def load_learned_patterns
        # Load learned patterns from Redis
        # Format: [{ keywords: ['nifty', 'rsi'], error_type: 'validation', error_count: 2, solution: '...' }, ...]
        patterns = []

        begin
          redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
          stored = redis.get('ai_agent:learned_patterns')
          patterns = JSON.parse(stored) if stored.present?
          redis.close
        rescue StandardError => e
          Rails.logger.warn("[TechnicalAnalysisAgent] Failed to load learned patterns: #{e.message}")
        end

        patterns
      end

      def save_learned_patterns
        # Save learned patterns to Redis
        return if @learned_patterns.empty?

        begin
          redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
          redis.set('ai_agent:learned_patterns', @learned_patterns.to_json)
          redis.expire('ai_agent:learned_patterns', 30.days.to_i) # Keep for 30 days
          redis.close
        rescue StandardError => e
          Rails.logger.warn("[TechnicalAnalysisAgent] Failed to save learned patterns: #{e.message}")
        end
      end

      def record_error(tool_name:, error_message:, query_keywords:)
        # Record error for learning
        error_type = classify_error(error_message)
        @error_history << {
          tool: tool_name,
          error: error_message,
          error_type: error_type,
          timestamp: Time.current
        }

        # Update learned patterns
        pattern = @learned_patterns.find { |p| p[:keywords] == query_keywords && p[:error_type] == error_type }
        if pattern
          pattern[:error_count] = (pattern[:error_count] || 0) + 1
          pattern[:last_seen] = Time.current
          pattern[:solution] = extract_solution(error_message) if pattern[:solution].blank?
        else
          @learned_patterns << {
            keywords: query_keywords,
            error_type: error_type,
            error_count: 1,
            last_seen: Time.current,
            solution: extract_solution(error_message)
          }
        end

        # Save patterns periodically (every 5 errors)
        save_learned_patterns if @error_history.size % 5 == 0
      end

      def classify_error(error_message)
        # Classify error type for learning
        case error_message.to_s
        when /validation|invalid|must be one of/i
          'validation'
        when /not found|missing|unavailable/i
          'not_found'
        when /timeout|connection|network/i
          'network'
        when /permission|access|unauthorized/i
          'permission'
        else
          'unknown'
        end
      end

      def extract_solution(error_message)
        # Extract solution hint from error message
        case error_message.to_s
        when /must be one of: (.*?)(?:\]|$)/i
          "Use one of: #{::Regexp.last_match(1)}"
        when /Missing (.*?)(?:\s|$)/i
          "Provide: #{::Regexp.last_match(1)}"
        when /Invalid (.*?)(?:\s|$)/i
          "Fix: #{::Regexp.last_match(1)}"
        else
          nil
        end
      end

      def build_learned_context
        # Build context from learned patterns to help AI avoid common mistakes
        return '' if @learned_patterns.empty?

        recent_patterns = @learned_patterns
                          .select { |p| p[:error_count].to_i >= 2 }
                          .sort_by { |p| p[:error_count] }
                          .last(5).reverse

        return '' if recent_patterns.empty?

        context = "\nLEARNED PATTERNS (common mistakes to avoid):\n"
        recent_patterns.each_with_index do |pattern, idx|
          context += "#{idx + 1}. When query involves: #{pattern[:keywords].join(', ')}\n"
          context += "   Common error: #{pattern[:error_type]}\n"
          context += "   Solution: #{pattern[:solution]}\n" if pattern[:solution].present?
          context += "   (Seen #{pattern[:error_count]} times)\n\n"
        end

        context
      end

      # Helper method to auto-detect exchange for known indices
      def detect_exchange_for_index(symbol_name, provided_exchange)
        # If exchange is explicitly provided, use it
        return provided_exchange.to_s.upcase if provided_exchange.present?

        # Auto-detect based on index name
        symbol_upper = symbol_name.to_s.upcase
        case symbol_upper
        when 'SENSEX'
          'BSE' # SENSEX is on BSE
        when 'NIFTY', 'BANKNIFTY', 'NIFTY50', 'NIFTY 50', 'BANKNIFTY50', 'BANK NIFTY'
          'NSE' # NIFTY and BANKNIFTY are on NSE
        else
          'NSE' # Default to NSE for unknown symbols (stocks are typically on NSE)
        end
      end

      # Helper method to auto-detect segment (index vs equity)
      def detect_segment_for_symbol(symbol_name, provided_segment)
        # If segment is explicitly provided, use it
        return provided_segment.to_s.downcase if provided_segment.present?

        # Auto-detect based on symbol name
        symbol_upper = symbol_name.to_s.upcase
        case symbol_upper
        when 'NIFTY', 'BANKNIFTY', 'SENSEX', 'NIFTY50', 'NIFTY 50', 'BANKNIFTY50', 'BANK NIFTY'
          'index' # Known indices
        else
          'equity' # Default to equity for stocks (RELIANCE, TCS, INFY, etc.)
        end
      end

      # Tool implementations
      def tool_get_comprehensive_analysis(args)
        underlying_symbol = args['underlying_symbol'] || args['symbol_name'] # Support both for backward compatibility
        return { error: 'Missing underlying_symbol' } unless underlying_symbol.present?

        # Auto-detect exchange and segment
        exchange = detect_exchange_for_index(underlying_symbol, args['exchange'])
        segment = detect_segment_for_symbol(underlying_symbol, args['segment'])
        interval = args['interval'] || '5'
        max_candles = [args['max_candles']&.to_i || 200, 200].min # Cap at 200

        return { error: 'Missing underlying_symbol' } unless underlying_symbol.present?

        # Find instrument using scopes
        instrument = case exchange
                     when 'NSE'
                       case segment
                       when 'index'
                         Instrument.nse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'equity'
                         Instrument.nse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'derivatives'
                         Instrument.nse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                       else
                         Instrument.nse.find_by(underlying_symbol: underlying_symbol.to_s)
                       end
                     when 'BSE'
                       case segment
                       when 'index'
                         Instrument.bse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'equity'
                         Instrument.bse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'derivatives'
                         Instrument.bse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                       else
                         Instrument.bse.find_by(underlying_symbol: underlying_symbol.to_s)
                       end
                     else
                       return { error: "Invalid exchange: #{exchange}. Must be 'NSE' or 'BSE'" }
                     end

        return { error: "Instrument not found: #{underlying_symbol} (#{exchange}, #{segment})" } unless instrument

        # Fetch LTP
        ltp = instrument.ltp

        # Normalize interval format (remove 'm' suffix if present)
        normalized_interval = interval.to_s.gsub(/m$/i, '')

        # Fetch historical data (candles)
        # Note: instrument.candles() automatically handles date ranges and includes today's data
        begin
          series = instrument.candles(interval: normalized_interval)
          return { error: "No candle data available for #{underlying_symbol}" } unless series&.candles&.any?

          # Limit to max_candles (take the most recent candles)
          candles = series.candles.last(max_candles)
          candle_count = candles.length
          latest_candle = candles.last
        rescue StandardError => e
          Rails.logger.error("[TechnicalAnalysisAgent] Error fetching candles: #{e.class} - #{e.message}")
          return { error: "Failed to fetch candle data for #{underlying_symbol}: #{e.message}" }
        end

        # Calculate ALL available indicators with interpretations
        indicators = {}
        indicator_interpretations = {}

        begin
          # RSI (14 period)
          rsi_value = series.rsi(14)
          if rsi_value.present?
            indicators[:rsi] = rsi_value
            # Add interpretation
            rsi_interpretation = if rsi_value < 30
                                   'oversold'
                                 elsif rsi_value > 70
                                   'overbought'
                                 elsif rsi_value < 50
                                   'neutral_bearish'
                                 elsif rsi_value > 50
                                   'neutral_bullish'
                                 else
                                   'neutral'
                                 end
            indicator_interpretations[:rsi] = rsi_interpretation
          end

          # MACD (12, 26, 9)
          macd_result = series.macd(12, 26, 9)
          if macd_result
            macd_line = macd_result[0]
            signal_line = macd_result[1]
            histogram = macd_result[2]
            indicators[:macd] = {
              macd: macd_line,
              signal: signal_line,
              histogram: histogram
            }
            # Add interpretation
            macd_interpretation = if macd_line > signal_line && histogram > 0
                                    'bullish'
                                  elsif macd_line < signal_line && histogram < 0
                                    'bearish'
                                  elsif macd_line > signal_line && histogram < 0
                                    'bullish_weakening'
                                  elsif macd_line < signal_line && histogram > 0
                                    'bearish_weakening'
                                  else
                                    'neutral'
                                  end
            indicator_interpretations[:macd] = macd_interpretation
          end

          # ADX (14 period)
          adx_value = series.adx(14)
          if adx_value.present?
            indicators[:adx] = adx_value
            # Add interpretation
            adx_interpretation = if adx_value < 20
                                   'weak_trend'
                                 elsif adx_value < 40
                                   'moderate_trend'
                                 elsif adx_value < 50
                                   'strong_trend'
                                 else
                                   'very_strong_trend'
                                 end
            indicator_interpretations[:adx] = adx_interpretation
          end

          # Supertrend (uses default period: 7, multiplier: 3.0 from CandleSeries)
          supertrend_value = series.supertrend_signal
          if supertrend_value.present?
            indicators[:supertrend] = supertrend_value
            # Add interpretation
            supertrend_interpretation = case supertrend_value.to_s
                                        when 'long_entry', :long_entry
                                          'bullish'
                                        when 'short_entry', :short_entry
                                          'bearish'
                                        else
                                          'neutral'
                                        end
            indicator_interpretations[:supertrend] = supertrend_interpretation
          end

          # ATR (14 period)
          atr_value = series.atr(14)
          if atr_value.present?
            indicators[:atr] = atr_value
            # ATR interpretation requires context (current price), so we'll just note it's available
            indicator_interpretations[:atr] = 'volatility_measure'
          end

          # Bollinger Bands (20 period, 2.0 std dev)
          bb_result = series.bollinger_bands(period: 20, std_dev: 2.0)
          if bb_result && latest_candle
            indicators[:bollinger_bands] = {
              upper: bb_result[:upper],
              middle: bb_result[:middle],
              lower: bb_result[:lower]
            }
            # Add interpretation based on current price position
            current_price = latest_candle.close
            bb_position = if current_price >= bb_result[:upper]
                            'near_upper_band'
                          elsif current_price <= bb_result[:lower]
                            'near_lower_band'
                          elsif current_price > bb_result[:middle]
                            'above_middle'
                          elsif current_price < bb_result[:middle]
                            'below_middle'
                          else
                            'at_middle'
                          end
            indicator_interpretations[:bollinger_bands] = bb_position
          end
        rescue StandardError => e
          Rails.logger.warn("[TechnicalAnalysisAgent] Error calculating some indicators: #{e.class} - #{e.message}")
          # Continue even if some indicators fail
        end

        # Get latest OHLC (latest_candle already defined above)
        ohlc = if latest_candle
                 {
                   open: latest_candle.open,
                   high: latest_candle.high,
                   low: latest_candle.low,
                   close: latest_candle.close,
                   volume: latest_candle.volume
                 }
               else
                 instrument.ohlc
               end

        {
          underlying_symbol: underlying_symbol,
          exchange: exchange,
          segment: segment,
          security_id: instrument.security_id,
          ltp: ltp.to_f,
          ohlc: ohlc,
          interval: interval,
          candle_count: candle_count,
          indicators: indicators,
          indicator_interpretations: indicator_interpretations,
          timestamp: Time.current
        }
      end

      def tool_get_index_ltp(args)
        index_key = args['index_key']&.to_s&.upcase

        # Cache index configs to avoid repeated lookups
        @index_config_cache ||= IndexConfigLoader.load_indices

        index_cfg = @index_config_cache.find { |idx| idx[:key].to_s.upcase == index_key }
        return { error: "Unknown index: #{index_key}" } unless index_cfg

        security_id = index_cfg[:security_id] || index_cfg[:sid]
        segment = index_cfg[:segment]
        return { error: "Missing security_id or segment for #{index_key}" } unless security_id && segment

        instrument = Instrument.find_by_sid_and_segment(
          security_id: security_id,
          segment_code: segment,
          underlying_symbol: index_key
        )
        return { error: "Instrument not found for #{index_key} (SID: #{security_id}, Segment: #{segment})" } unless instrument

        ltp = instrument.ltp

        {
          index: index_key,
          ltp: ltp,
          timestamp: Time.current
        }
      end

      def tool_get_instrument_ltp(args)
        underlying_symbol = args['underlying_symbol'] || args['symbol_name'] # Support both for backward compatibility
        return { error: 'Missing underlying_symbol' } unless underlying_symbol.present?

        # Auto-detect exchange and segment
        exchange = detect_exchange_for_index(underlying_symbol, args['exchange'])
        segment = detect_segment_for_symbol(underlying_symbol, args['segment'])

        # Find instrument using scopes
        instrument = case exchange
                     when 'NSE'
                       case segment
                       when 'index'
                         Instrument.nse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'equity'
                         Instrument.nse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'derivatives'
                         Instrument.nse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                       else
                         Instrument.nse.find_by(underlying_symbol: underlying_symbol.to_s)
                       end
                     when 'BSE'
                       case segment
                       when 'index'
                         Instrument.bse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'equity'
                         Instrument.bse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'derivatives'
                         Instrument.bse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                       else
                         Instrument.bse.find_by(underlying_symbol: underlying_symbol.to_s)
                       end
                     else
                       return { error: "Invalid exchange: #{exchange}. Must be 'NSE' or 'BSE'" }
                     end

        return { error: "Instrument not found: #{underlying_symbol} (#{exchange}, #{segment})" } unless instrument

        ltp = instrument.ltp
        return { error: 'LTP not available' } unless ltp

        {
          underlying_symbol: underlying_symbol,
          exchange: exchange,
          segment: segment,
          security_id: instrument.security_id,
          ltp: ltp.to_f,
          timestamp: Time.current
        }
      end

      def tool_get_ohlc(args)
        underlying_symbol = args['underlying_symbol'] || args['symbol_name'] # Support both for backward compatibility
        return { error: 'Missing underlying_symbol' } unless underlying_symbol.present?

        # Auto-detect exchange and segment
        exchange = detect_exchange_for_index(underlying_symbol, args['exchange'])
        segment = detect_segment_for_symbol(underlying_symbol, args['segment'])

        # Find instrument using scopes
        instrument = case exchange
                     when 'NSE'
                       case segment
                       when 'index'
                         Instrument.nse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'equity'
                         Instrument.nse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'derivatives'
                         Instrument.nse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                       else
                         Instrument.nse.find_by(underlying_symbol: underlying_symbol.to_s)
                       end
                     when 'BSE'
                       case segment
                       when 'index'
                         Instrument.bse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'equity'
                         Instrument.bse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'derivatives'
                         Instrument.bse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                       else
                         Instrument.bse.find_by(underlying_symbol: underlying_symbol.to_s)
                       end
                     else
                       return { error: "Invalid exchange: #{exchange}. Must be 'NSE' or 'BSE'" }
                     end

        return { error: "Instrument not found: #{underlying_symbol} (#{exchange}, #{segment})" } unless instrument

        ohlc_data = instrument.ohlc
        return { error: 'OHLC data not available' } unless ohlc_data

        {
          underlying_symbol: underlying_symbol,
          exchange: exchange,
          segment: segment,
          security_id: instrument.security_id,
          ohlc: ohlc_data,
          timestamp: Time.current
        }
      end

      def tool_calculate_indicator(args)
        index_key = args['index_key']&.to_s&.upcase
        indicator_name = args['indicator']&.to_s&.downcase
        period = args['period']&.to_i
        interval = args['interval'] || '1'

        index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == index_key }
        return { error: "Unknown index: #{index_key}" } unless index_cfg

        security_id = index_cfg[:security_id] || index_cfg[:sid]
        segment = index_cfg[:segment]
        return { error: "Missing security_id or segment for #{index_key}" } unless security_id && segment

        # Get instrument and candle series using both security_id and segment
        instrument = Instrument.find_by_sid_and_segment(
          security_id: security_id,
          segment_code: segment,
          underlying_symbol: index_key
        )
        return { error: "Instrument not found for #{index_key} (SID: #{security_id}, Segment: #{segment})" } unless instrument

        # Normalize interval format (remove 'm' suffix if present, e.g., "1m" -> "1")
        normalized_interval = interval.to_s.gsub(/m$/i, '')

        begin
          series = instrument.candles(interval: normalized_interval)
          return { error: "No candle data available for #{index_key}" } unless series&.candles&.any?
        rescue StandardError => e
          Rails.logger.error("[TechnicalAnalysisAgent] Error fetching candles: #{e.class} - #{e.message}")
          return { error: "Failed to fetch candle data for #{index_key}: #{e.message}" }
        end

        # Calculate indicator using CandleSeries methods
        result = case indicator_name
                 when 'rsi'
                   rsi_period = period || 14
                   series.rsi(rsi_period)
                 when 'macd'
                   fast = period || 12
                   slow = period ? period * 2 : 26
                   signal = period ? (period * 0.75).to_i : 9
                   macd_result = series.macd(fast, slow, signal)
                   macd_result ? { macd: macd_result[0], signal: macd_result[1], histogram: macd_result[2] } : nil
                 when 'adx'
                   adx_period = period || 14
                   series.adx(adx_period)
                 when 'supertrend'
                   st_period = period || 7
                   multiplier = args['multiplier']&.to_f || 3.0
                   series.supertrend_signal(period: st_period, multiplier: multiplier)
                 when 'atr'
                   atr_period = period || 14
                   series.atr(atr_period)
                 when 'bollinger', 'bollingerbands', 'bb'
                   bb_period = period || 20
                   std_dev = args['std_dev']&.to_f || 2.0
                   bb_result = series.bollinger_bands(period: bb_period, std_dev: std_dev)
                   bb_result ? { upper: bb_result[:upper], middle: bb_result[:middle], lower: bb_result[:lower] } : nil
                 else
                   return { error: "Unknown indicator: #{indicator_name}. Available: RSI, MACD, ADX, Supertrend, ATR, BollingerBands" }
                 end

        {
          index: index_key,
          indicator: indicator_name,
          period: period,
          interval: interval,
          value: result,
          timestamp: Time.current
        }
      end

      def tool_get_historical_data(args)
        underlying_symbol = args['underlying_symbol'] || args['symbol_name'] # Support both for backward compatibility
        return { error: 'Missing underlying_symbol' } unless underlying_symbol.present?

        # Auto-detect exchange and segment
        exchange = detect_exchange_for_index(underlying_symbol, args['exchange'])
        segment = detect_segment_for_symbol(underlying_symbol, args['segment'])
        interval = args['interval'] || '5'
        days = args['days']&.to_i || 3

        # Parse and validate dates
        to_date = if args['to_date'].present?
                    Date.parse(args['to_date'].to_s)
                  else
                    Time.zone.today
                  end

        from_date = if args['from_date'].present?
                      Date.parse(args['from_date'].to_s)
                    else
                      to_date - days.days
                    end

        # Ensure from_date is at least 1 day before to_date
        from_date = to_date - 1.day if from_date >= to_date

        # Find instrument using scopes
        # Map segment string to enum value for Instrument model
        segment_enum = case segment
                       when 'index' then 'index'
                       when 'equity' then 'equity'
                       when 'derivatives' then 'derivatives'
                       when 'currency' then 'currency'
                       when 'commodity' then 'commodity'
                       else segment # fallback
                       end

        instrument = case exchange
                     when 'NSE'
                       case segment_enum
                       when 'index'
                         Instrument.nse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'equity'
                         Instrument.nse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'derivatives'
                         Instrument.nse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                       else
                         Instrument.nse.find_by(underlying_symbol: underlying_symbol.to_s)
                       end
                     when 'BSE'
                       case segment_enum
                       when 'index'
                         Instrument.bse.segment_index.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'equity'
                         Instrument.bse.segment_equity.find_by(underlying_symbol: underlying_symbol.to_s)
                       when 'derivatives'
                         Instrument.bse.segment_derivatives.find_by(underlying_symbol: underlying_symbol.to_s)
                       else
                         Instrument.bse.find_by(underlying_symbol: underlying_symbol.to_s)
                       end
                     else
                       return { error: "Invalid exchange: #{exchange}. Must be 'NSE' or 'BSE'" }
                     end

        return { error: "Instrument not found: #{underlying_symbol} (#{exchange}, #{segment})" } unless instrument

        # Normalize interval format (remove 'm' suffix if present, e.g., "15m" -> "15")
        # DhanHQ expects: "1", "5", "15", "25", "60" (not "1m", "15m", etc.)
        normalized_interval = interval.to_s.gsub(/m$/i, '')

        # Validate interval is one of the allowed values
        allowed_intervals = %w[1 5 15 25 60]
        unless allowed_intervals.include?(normalized_interval)
          return { error: "Invalid interval: #{interval}. Must be one of: #{allowed_intervals.join(', ')}" }
        end

        begin
          # Convert Date objects to strings in YYYY-MM-DD format for API call
          from_date_str = from_date.strftime('%Y-%m-%d')
          to_date_str = to_date.strftime('%Y-%m-%d')

          # Use instrument helper method - it handles all the complexity internally
          # This includes: resolve_instrument_code, exchange_segment, error handling, date defaults
          data = instrument.intraday_ohlc(
            interval: normalized_interval,
            from_date: from_date_str,
            to_date: to_date_str,
            days: days
          )

          return { error: 'No historical data available' } unless data.present?

          {
            underlying_symbol: underlying_symbol,
            exchange: exchange,
            segment: segment,
            security_id: instrument.security_id,
            exchange_segment: instrument.exchange_segment,
            interval: normalized_interval,
            from_date: from_date_str,
            to_date: to_date_str,
            candles: data.is_a?(Array) ? data.first(100) : [], # Limit to 100 candles
            count: data.is_a?(Array) ? data.size : 0
          }
        rescue StandardError => e
          Rails.logger.error("[TechnicalAnalysisAgent] Historical data error: #{e.class} - #{e.message}")
          { error: "#{e.class}: #{e.message}" }
        end
      end

      def tool_analyze_option_chain(args)
        index_key = args['index_key']&.to_s&.upcase
        direction = (args['direction'] || 'bullish').to_sym
        limit = args['limit']&.to_i || 5

        # Cache analyzer instance to avoid repeated initialization
        cache_key = "analyzer:#{index_key}"
        @analyzer_cache ||= {}
        analyzer = @analyzer_cache[cache_key] ||= Options::DerivativeChainAnalyzer.new(index_key: index_key)

        candidates = analyzer.select_candidates(limit: limit, direction: direction)

        {
          index: index_key,
          direction: direction,
          candidates: candidates.map do |c|
            {
              strike: c[:strike],
              type: c[:type],
              ltp: c[:ltp],
              premium: c[:premium],
              score: c[:score]
            }
          end
        }
      end

      def tool_get_trading_stats(args)
        date = args['date'] ? Date.parse(args['date']) : Time.zone.today
        stats = PositionTracker.paper_trading_stats_with_pct(date: date)

        {
          date: date.to_s,
          total_trades: stats[:total_trades],
          winners: stats[:winners],
          losers: stats[:losers],
          win_rate: stats[:win_rate],
          realized_pnl: stats[:realized_pnl_rupees],
          realized_pnl_pct: stats[:realized_pnl_pct]
        }
      end

      def tool_get_active_positions(_args)
        positions = PositionTracker.paper.active

        {
          count: positions.count,
          positions: positions.map do |p|
            {
              symbol: p.symbol,
              entry_price: p.entry_price,
              quantity: p.quantity,
              current_pnl: p.last_pnl_rupees,
              current_pnl_pct: (p.last_pnl_pct || 0) * 100
            }
          end
        }
      end

      def tool_calculate_advanced_indicator(args)
        index_key = args['index_key']&.to_s&.upcase
        indicator_name = args['indicator']&.to_s&.downcase
        interval = args['interval'] || '5'
        config = args['config'] || {}

        # Cache index configs
        @index_config_cache ||= IndexConfigLoader.load_indices

        index_cfg = @index_config_cache.find { |idx| idx[:key].to_s.upcase == index_key }
        return { error: "Unknown index: #{index_key}" } unless index_cfg

        security_id = index_cfg[:security_id] || index_cfg[:sid]
        segment = index_cfg[:segment]
        return { error: "Missing security_id or segment for #{index_key}" } unless security_id && segment

        instrument = Instrument.find_by_sid_and_segment(
          security_id: security_id,
          segment_code: segment,
          underlying_symbol: index_key
        )
        return { error: "Instrument not found for #{index_key}" } unless instrument

        # Normalize interval
        normalized_interval = interval.to_s.gsub(/m$/i, '')

        begin
          series = instrument.candles(interval: normalized_interval)
          return { error: "No candle data available for #{index_key}" } unless series&.candles&.any?

          result = case indicator_name
                   when 'holygrail', 'holy_grail'
                     holy_grail_result = Indicators::HolyGrail.new(
                       candles: series.candles,
                       config: config.deep_symbolize_keys
                     ).call
                     {
                       bias: holy_grail_result.bias,
                       adx: holy_grail_result.adx,
                       momentum: holy_grail_result.momentum,
                       proceed: holy_grail_result.proceed?,
                       sma50: holy_grail_result.sma50,
                       ema200: holy_grail_result.ema200,
                       rsi14: holy_grail_result.rsi14,
                       atr14: holy_grail_result.atr14,
                       macd: holy_grail_result.macd,
                       trend: holy_grail_result.trend
                     }
                   when 'trendduration', 'trend_duration'
                     indicator = Indicators::TrendDurationIndicator.new(
                       series: series,
                       config: config.deep_symbolize_keys
                     )
                     last_result = indicator.calculate_at(series.candles.size - 1)
                     {
                       trend_direction: last_result[:trend_direction],
                       duration: last_result[:duration],
                       confidence: last_result[:confidence],
                       probable_duration: last_result[:probable_duration]
                     }
                   else
                     return { error: "Unknown advanced indicator: #{indicator_name}. Available: HolyGrail, TrendDuration" }
                   end

          {
            index: index_key,
            indicator: indicator_name,
            interval: normalized_interval,
            result: result,
            timestamp: Time.current
          }
        rescue StandardError => e
          Rails.logger.error("[TechnicalAnalysisAgent] Advanced indicator error: #{e.class} - #{e.message}")
          { error: "#{e.class}: #{e.message}" }
        end
      end

      def tool_run_backtest(args)
        index_key = args['index_key']&.to_s&.upcase
        interval = args['interval'] || '5'
        days_back = args['days_back']&.to_i || 90
        supertrend_cfg = args['supertrend_cfg'] || {}
        adx_min_strength = args['adx_min_strength']&.to_f || 0

        # Cache index configs
        @index_config_cache ||= IndexConfigLoader.load_indices

        index_cfg = @index_config_cache.find { |idx| idx[:key].to_s.upcase == index_key }
        return { error: "Unknown index: #{index_key}" } unless index_cfg

        symbol = index_key # BacktestService expects symbol name

        begin
          # Use BacktestServiceWithNoTradeEngine for comprehensive backtesting
          service = BacktestServiceWithNoTradeEngine.run(
            symbol: symbol,
            interval_1m: '1',
            interval_5m: interval,
            days_back: days_back,
            supertrend_cfg: supertrend_cfg.deep_symbolize_keys,
            adx_min_strength: adx_min_strength
          )

          summary = service.summary
          {
            index: index_key,
            interval: interval,
            days_back: days_back,
            summary: {
              total_trades: summary[:total_trades],
              winning_trades: summary[:winning_trades],
              losing_trades: summary[:losing_trades],
              win_rate: summary[:win_rate],
              avg_win_percent: summary[:avg_win_percent],
              avg_loss_percent: summary[:avg_loss_percent],
              total_pnl_percent: summary[:total_pnl_percent],
              expectancy: summary[:expectancy],
              max_win: summary[:max_win],
              max_loss: summary[:max_loss]
            },
            no_trade_stats: service.no_trade_stats,
            timestamp: Time.current
          }
        rescue StandardError => e
          Rails.logger.error("[TechnicalAnalysisAgent] Backtest error: #{e.class} - #{e.message}")
          { error: "#{e.class}: #{e.message}" }
        end
      end

      def tool_optimize_indicator(args)
        index_key = args['index_key']&.to_s&.upcase
        interval = args['interval'] || '5'
        lookback_days = args['lookback_days']&.to_i || 45
        test_mode = args['test_mode'] == true

        # Cache index configs
        @index_config_cache ||= IndexConfigLoader.load_indices

        index_cfg = @index_config_cache.find { |idx| idx[:key].to_s.upcase == index_key }
        return { error: "Unknown index: #{index_key}" } unless index_cfg

        security_id = index_cfg[:security_id] || index_cfg[:sid]
        segment = index_cfg[:segment]
        return { error: "Missing security_id or segment for #{index_key}" } unless security_id && segment

        instrument = Instrument.find_by_sid_and_segment(
          security_id: security_id,
          segment_code: segment,
          underlying_symbol: index_key
        )
        return { error: "Instrument not found for #{index_key}" } unless instrument

        begin
          optimizer = Optimization::IndicatorOptimizer.new(
            instrument: instrument,
            interval: interval,
            lookback_days: lookback_days,
            test_mode: test_mode
          )

          result = optimizer.run

          return { error: result[:error] } if result[:error]

          {
            index: index_key,
            interval: interval,
            lookback_days: lookback_days,
            test_mode: test_mode,
            best_params: result[:params],
            best_score: result[:score],
            best_metrics: result[:metrics],
            timestamp: Time.current
          }
        rescue StandardError => e
          Rails.logger.error("[TechnicalAnalysisAgent] Optimization error: #{e.class} - #{e.message}")
          { error: "#{e.class}: #{e.message}" }
        end
      end
    end
  end
end
