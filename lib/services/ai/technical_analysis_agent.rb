# frozen_string_literal: true

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
      end

      def analyze(query:, stream: false, &)
        return nil unless @client.enabled?

        # Clear caches for new conversation
        @tool_cache = {}
        @index_config_cache = nil
        @analyzer_cache = {}

        # Build system prompt with available tools
        system_prompt = build_system_prompt

        # Add current date context to user query
        current_date = Time.zone.today.strftime('%Y-%m-%d')
        enhanced_query = "#{query}\n\nIMPORTANT: Today's date is #{current_date}. Always use current dates (not past dates like 2023)."

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
          You are an expert technical analysis agent for Indian index options trading (NIFTY, BANKNIFTY, SENSEX).

          You have access to the following tools:
          #{format_tools_for_prompt}

          When analyzing markets, you can:
          1. Fetch real-time market data (LTP, OHLC) for indices and instruments
          2. Calculate technical indicators (RSI, MACD, ADX, Supertrend, etc.)
          3. Analyze option chains and derivative data
          4. Query historical price data
          5. Get current positions and trading statistics

          Use the available tools to gather data before providing analysis.
          Provide actionable, data-driven insights based on the tools you use.

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
          2. Respond with ONLY the JSON tool call, nothing else
          3. After receiving tool results, provide your analysis
          4. Use CURRENT dates (today is #{Time.zone.today.strftime('%Y-%m-%d')}) - never use old dates like 2023
          5. Be efficient - try to get all needed data in 1-2 tool calls
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
          'get_index_ltp' => {
            description: 'Get Last Traded Price (LTP) for an index (NIFTY, BANKNIFTY, SENSEX)',
            parameters: [
              { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' }
            ],
            handler: method(:tool_get_index_ltp)
          },
          'get_instrument_ltp' => {
            description: 'Get LTP for a specific instrument by security_id and segment',
            parameters: [
              { name: 'security_id', type: 'string', description: 'Security ID of the instrument' },
              { name: 'segment', type: 'string', description: 'Exchange segment (e.g., IDX_I, NSE_FNO)' }
            ],
            handler: method(:tool_get_instrument_ltp)
          },
          'get_ohlc' => {
            description: 'Get OHLC (Open, High, Low, Close) data for an instrument',
            parameters: [
              { name: 'security_id', type: 'string', description: 'Security ID' },
              { name: 'segment', type: 'string', description: 'Exchange segment' }
            ],
            handler: method(:tool_get_ohlc)
          },
          'calculate_indicator' => {
            description: 'Calculate a technical indicator for an index',
            parameters: [
              { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' },
              { name: 'indicator', type: 'string',
                description: 'Indicator name: RSI, MACD, ADX, Supertrend, ATR, BollingerBands' },
              { name: 'period', type: 'integer',
                description: 'Period for the indicator (optional, defaults vary by indicator)' },
              { name: 'interval', type: 'string', description: 'Timeframe: 1, 5, 15, 30, 60 (minutes) or daily' }
            ],
            handler: method(:tool_calculate_indicator)
          },
          'get_historical_data' => {
            description: 'Get historical price data (candles) for an instrument',
            parameters: [
              { name: 'security_id', type: 'string', description: 'Security ID' },
              { name: 'segment', type: 'string', description: 'Exchange segment' },
              { name: 'interval', type: 'string',
                description: 'Timeframe: 1, 5, 15, 25, 60 (minutes). Must be one of: 1, 5, 15, 25, 60. Can use "1", "5", "15m", etc. - will be normalized' },
              { name: 'from_date', type: 'string', description: 'Start date (YYYY-MM-DD)' },
              { name: 'to_date', type: 'string', description: 'End date (YYYY-MM-DD)' }
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

      def execute_conversation(messages:, model:, max_iterations: 3)
        iteration = 0
        full_response = ''

        Rails.logger.debug { "[TechnicalAnalysisAgent] Starting conversation (max_iterations: #{max_iterations})" }

        while iteration < max_iterations
          Rails.logger.debug { "[TechnicalAnalysisAgent] Iteration #{iteration + 1}/#{max_iterations}" }

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
            Rails.logger.debug { "[TechnicalAnalysisAgent] Tool call: #{tool_call['tool']}" }

            # Execute tool
            tool_result = execute_tool(tool_call)

            # Add assistant message and tool result to conversation
            # Limit message history to last 10 messages to avoid token bloat
            messages << { role: 'assistant', content: response }
            messages << {
              role: 'tool',
              content: "Tool: #{tool_call['tool']}\nResult: #{JSON.pretty_generate(tool_result)}"
            }

            # Keep only last 10 messages (system + recent conversation)
            messages = [messages.first] + messages.last(11) if messages.size > 12 # system + 10 messages

            iteration += 1
            next
          end

          # No tool call - final response
          Rails.logger.info('[TechnicalAnalysisAgent] Analysis complete')
          full_response = response
          break
        end

        if iteration >= max_iterations
          Rails.logger.warn("[TechnicalAnalysisAgent] Reached max iterations (#{max_iterations})")
        end

        Rails.logger.info("[TechnicalAnalysisAgent] Completed in #{iteration} iteration(s)")

        {
          analysis: full_response,
          generated_at: Time.current,
          provider: @client.provider
        }
      rescue StandardError => e
        Rails.logger.error("[TechnicalAnalysisAgent] Error: #{e.class} - #{e.message}")
        Rails.logger.error("[TechnicalAnalysisAgent] Backtrace: #{e.backtrace.first(5).join("\n")}")
        nil
      end

      def execute_conversation_stream(messages:, model:, max_iterations: 3, &block)
        iteration = 0
        full_response = +''

        Rails.logger.info("[TechnicalAnalysisAgent] Starting analysis (streaming, max_iterations: #{max_iterations})")

        while iteration < max_iterations
          Rails.logger.info("[TechnicalAnalysisAgent] Iteration #{iteration + 1}/#{max_iterations}")

          response_chunks = +''
          chunk_count = 0

          @client.chat_stream(
            messages: messages,
            model: model,
            temperature: 0.3
          ) do |chunk|
            if chunk
              response_chunks << chunk
              chunk_count += 1
              yield(chunk) if block
            end
          end

          response = response_chunks
          full_response << response

          # Check if response contains tool call
          tool_call = extract_tool_call(response)
          if tool_call
            Rails.logger.info("[TechnicalAnalysisAgent] Executing tool: #{tool_call['tool']}")

            # Execute tool
            tool_result = execute_tool(tool_call)

            Rails.logger.info("[TechnicalAnalysisAgent] Tool completed: #{tool_call['tool']}")

            # Add assistant message and tool result to conversation
            # Limit message history to last 10 messages to avoid token bloat
            messages << { role: 'assistant', content: response }
            messages << {
              role: 'tool',
              content: "Tool: #{tool_call['tool']}\nResult: #{JSON.pretty_generate(tool_result)}"
            }

            # Keep only last 10 messages (system + recent conversation)
            messages = [messages.first] + messages.last(11) if messages.size > 12 # system + 10 messages

            iteration += 1
            next
          end

          # No tool call - final response
          Rails.logger.info('[TechnicalAnalysisAgent] Analysis complete')
          break
        end

        if iteration >= max_iterations
          Rails.logger.warn("[TechnicalAnalysisAgent] Reached max iterations (#{max_iterations})")
        end

        Rails.logger.info("[TechnicalAnalysisAgent] Completed in #{iteration} iteration(s)")

        {
          analysis: full_response,
          generated_at: Time.current,
          provider: @client.provider
        }
      rescue StandardError => e
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
          { error: "#{e.class}: #{e.message}" }
        end
      end

      # Tool implementations
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
          symbol_name: index_key
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
        security_id = args['security_id']
        segment = args['segment']

        return { error: 'Missing security_id or segment' } unless security_id && segment

        instrument = Instrument.find_by_sid_and_segment(
          security_id: security_id,
          segment_code: segment
        )
        return { error: "Instrument not found (SID: #{security_id}, Segment: #{segment})" } unless instrument

        ltp = instrument.ltp
        {
          security_id: security_id,
          segment: segment,
          ltp: ltp,
          symbol: instrument.symbol_name,
          timestamp: Time.current
        }
      end

      def tool_get_ohlc(args)
        security_id = args['security_id']
        segment = args['segment']

        return { error: 'Missing security_id or segment' } unless security_id && segment

        instrument = Instrument.find_by_sid_and_segment(
          security_id: security_id,
          segment_code: segment
        )
        return { error: "Instrument not found (SID: #{security_id}, Segment: #{segment})" } unless instrument

        ohlc_data = instrument.ohlc
        {
          security_id: security_id,
          segment: segment,
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
          symbol_name: index_key
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
                 else
                   return { error: "Unknown indicator: #{indicator_name}. Available: RSI, MACD, ADX, Supertrend, ATR" }
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
        security_id = args['security_id']
        segment = args['segment']
        interval = args['interval'] || '5'
        from_date = args['from_date']
        to_date = args['to_date'] || Time.zone.today.strftime('%Y-%m-%d')

        # Validate and fix dates - ensure they're not in the past (2023, etc.)
        current_year = Time.zone.today.year
        if from_date
          begin
            from_year = Date.parse(from_date).year
            if from_year < current_year
              Rails.logger.warn("[TechnicalAnalysisAgent] Invalid from_date (#{from_date}), using default (3 days ago)")
              from_date = (Time.zone.today - 3.days).strftime('%Y-%m-%d')
            end
          rescue ArgumentError
            Rails.logger.warn("[TechnicalAnalysisAgent] Invalid from_date format (#{from_date}), using default (3 days ago)")
            from_date = (Time.zone.today - 3.days).strftime('%Y-%m-%d')
          end
        else
          from_date = (Time.zone.today - 3.days).strftime('%Y-%m-%d')
        end

        if to_date
          begin
            to_year = Date.parse(to_date).year
            if to_year < current_year
              Rails.logger.warn("[TechnicalAnalysisAgent] Invalid to_date (#{to_date}), using today")
              to_date = Time.zone.today.strftime('%Y-%m-%d')
            end
          rescue ArgumentError
            Rails.logger.warn("[TechnicalAnalysisAgent] Invalid to_date format (#{to_date}), using today")
            to_date = Time.zone.today.strftime('%Y-%m-%d')
          end
        end

        # Normalize interval format (remove 'm' suffix if present, e.g., "15m" -> "15")
        # DhanHQ expects: "1", "5", "15", "25", "60" (not "1m", "15m", etc.)
        normalized_interval = interval.to_s.gsub(/m$/i, '')

        # Validate interval is one of the allowed values
        allowed_intervals = %w[1 5 15 25 60]
        unless allowed_intervals.include?(normalized_interval)
          return { error: "Invalid interval: #{interval}. Must be one of: #{allowed_intervals.join(', ')}" }
        end

        begin
          data = DhanHQ::Models::HistoricalData.intraday(
            security_id: security_id,
            exchange_segment: segment,
            instrument: 'INDEX',
            interval: normalized_interval,
            from_date: from_date,
            to_date: to_date
          )

          {
            security_id: security_id,
            segment: segment,
            interval: normalized_interval,
            from_date: from_date,
            to_date: to_date,
            candles: data&.first(100), # Limit to 100 candles
            count: data&.size || 0
          }
        rescue StandardError => e
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
          symbol_name: index_key
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
          symbol_name: index_key
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
