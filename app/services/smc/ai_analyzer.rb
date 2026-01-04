# frozen_string_literal: true

module Smc
  # AI-powered SMC analysis using chat completion with history and tool calling
  class AiAnalyzer
    MAX_ITERATIONS = ENV.fetch('SMC_AI_MAX_ITERATIONS', '10').to_i
    MAX_MESSAGE_HISTORY = ENV.fetch('SMC_AI_MAX_MESSAGE_HISTORY', '12').to_i

    def initialize(instrument, initial_data:)
      @instrument = instrument
      @initial_data = initial_data
      @messages = []
      @tool_cache = {}
      @ai_client = Services::Ai::OpenaiClient.instance
      @model = select_model
    end

    def analyze(stream: false, &block)
      return nil unless ai_enabled?

      initialize_conversation

      if stream && block_given?
        execute_conversation_stream(&block)
      else
        execute_conversation
      end
    rescue StandardError => e
      Rails.logger.error("[Smc::AiAnalyzer] Error: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      nil
    end

    private

    def ai_enabled?
      AlgoConfig.fetch.dig(:ai, :enabled) == true && @ai_client.enabled?
    rescue StandardError
      false
    end

    def select_model
      if @ai_client.provider == :ollama
        @ai_client.selected_model || ENV['OLLAMA_MODEL'] || 'llama3.2:3b'
      else
        'gpt-4o'
      end
    end

    def initialize_conversation
      @messages = [
        {
          role: 'system',
          content: system_prompt
        },
        {
          role: 'user',
          content: initial_analysis_prompt
        }
      ]
    end

    def system_prompt
      <<~PROMPT
        You are an expert Smart Money Concepts (SMC) and market structure analyst specializing in Indian index options trading (NIFTY, BANKNIFTY, SENSEX).

        You analyze market structure, liquidity, premium/discount zones, order blocks, and AVRZ rejections to provide actionable trading insights.

        You have access to tools to fetch additional market data if needed. Use them when you need:
        - Current LTP (last traded price)
        - Historical candle data for deeper analysis
        - Technical indicators (RSI, MACD, ADX, Supertrend) for confirmation
        - Option chain data for strike selection

        Provide clear, actionable analysis focused on practical trading decisions.
      PROMPT
    end

    def initial_analysis_prompt
      symbol_name = @instrument.symbol_name || 'UNKNOWN'
      decision = @initial_data[:decision]

      <<~PROMPT
        Analyze the following SMC/AVRZ market structure data for #{symbol_name}:

        Trading Decision: #{decision}

        Market Structure Analysis (Multi-Timeframe):

        #{JSON.pretty_generate(@initial_data[:timeframes])}

        Please provide:
        1. **Market Structure Summary**: Overall trend, structure breaks, and change of character signals
        2. **Liquidity Assessment**: Where liquidity is being taken and potential sweep zones
        3. **Premium/Discount Analysis**: Current market position relative to equilibrium
        4. **Order Block Significance**: Key order blocks and their relevance
        5. **FVG Analysis**: Fair value gaps and their trading implications
        6. **AVRZ Confirmation**: Rejection signals and timing confirmation
        7. **Trading Recommendation**: Validate or challenge the #{decision} decision with reasoning
        8. **Risk Factors**: Key risks and considerations for this setup
        9. **Entry Strategy**: Optimal entry approach if trading signal is valid

        If you need additional data (current price, indicators, option chain), use the available tools.
        Focus on actionable insights for options trading.
      PROMPT
    end

    def execute_conversation
      iteration = 0
      full_response = ''

      while iteration < MAX_ITERATIONS
        Rails.logger.debug { "[Smc::AiAnalyzer] Iteration #{iteration + 1}/#{MAX_ITERATIONS}" }

        # Prepare tools for this request
        tools = build_tools_definition

        # Make chat request with tools
        response = @ai_client.chat(
          messages: limit_message_history(@messages),
          model: @model,
          temperature: 0.3,
          tools: tools,
          tool_choice: 'auto'
        )

        unless response
          Rails.logger.warn('[Smc::AiAnalyzer] No response from AI client')
          break
        end

        # Extract content and tool_calls from response
        # Response format depends on whether tools were used
        if response.is_a?(Hash)
          # When tools are used, response is a hash with content and tool_calls
          content = response[:content] || response['content']
          tool_calls = response[:tool_calls] || response['tool_calls']
        elsif response.is_a?(String)
          # When no tools, response is just content string
          content = response
          tool_calls = nil
        else
          # Try to extract from response object
          content = response.respond_to?(:content) ? response.content : response.to_s
          tool_calls = response.respond_to?(:tool_calls) ? response.tool_calls : nil
        end

        # Check if response contains tool calls (native format)
        if tool_calls&.any?
          Rails.logger.debug { "[Smc::AiAnalyzer] Tool calls detected: #{tool_calls.map { |tc| tc['function']['name'] }.join(', ')}" }

          # Add assistant message with tool calls
          formatted_tool_calls = tool_calls.map do |tc|
            tc_hash = tc.is_a?(Hash) ? tc : tc.to_h
            {
              id: tc_hash['id'] || tc_hash[:id] || SecureRandom.hex(8),
              type: 'function',
              function: {
                name: (tc_hash['function'] || tc_hash[:function] || {})['name'] || (tc_hash['function'] || tc_hash[:function] || {})[:name],
                arguments: ((tc_hash['function'] || tc_hash[:function] || {})['arguments'] || (tc_hash['function'] || tc_hash[:function] || {})[:arguments]).to_json
              }
            }
          end

          @messages << {
            role: 'assistant',
            content: content,
            tool_calls: formatted_tool_calls
          }

          # Execute tools and add results
          tool_calls.each do |tool_call|
            tc_hash = tool_call.is_a?(Hash) ? tool_call : tool_call.to_h
            func = tc_hash['function'] || tc_hash[:function] || {}
            tool_name = func['name'] || func[:name]
            tool_args_raw = func['arguments'] || func[:arguments]
            tool_args = tool_args_raw.is_a?(String) ? JSON.parse(tool_args_raw) : tool_args_raw

            Rails.logger.debug { "[Smc::AiAnalyzer] Executing tool: #{tool_name} with args: #{tool_args.inspect}" }

            tool_result = execute_tool(tool_name, tool_args)

            tc_hash = tool_call.is_a?(Hash) ? tool_call : tool_call.to_h
            @messages << {
              role: 'tool',
              tool_call_id: tc_hash['id'] || tc_hash[:id] || SecureRandom.hex(8),
              name: tool_name,
              content: JSON.pretty_generate(tool_result)
            }
          end

          # Add user message prompting for analysis
          @messages << {
            role: 'user',
            content: 'Based on the tool results, continue your analysis. If you have all the data you need, provide your complete analysis now.'
          }

          iteration += 1
          next
        end

        # No tool calls - final response
        full_response = content || response.to_s
        Rails.logger.info('[Smc::AiAnalyzer] Final analysis received')
        break
      end

      if iteration >= MAX_ITERATIONS
        Rails.logger.warn("[Smc::AiAnalyzer] Reached max iterations (#{MAX_ITERATIONS})")
      end

      full_response.presence
    end

    def execute_conversation_stream(&_block)
      iteration = 0
      full_response = +''

      while iteration < MAX_ITERATIONS
        Rails.logger.debug { "[Smc::AiAnalyzer] Stream iteration #{iteration + 1}/#{MAX_ITERATIONS}" }

        tools = build_tools_definition

        # Stream response
        stream_response = nil
        @ai_client.chat_stream(
          messages: limit_message_history(@messages),
          model: @model,
          temperature: 0.3,
          tools: tools,
          tool_choice: 'auto'
        ) do |chunk|
          stream_response ||= +''
          stream_response << chunk if chunk.present?
          yield(chunk) if block_given?
        end

        unless stream_response
          Rails.logger.warn('[Smc::AiAnalyzer] No stream response')
          break
        end

        # Check for tool calls in streamed response
        tool_calls = extract_tool_calls_from_text(stream_response)
        if tool_calls&.any?
          Rails.logger.info { "[Smc::AiAnalyzer] Tool calls detected in stream: #{tool_calls.map { |tc| tc['tool'] || tc[:tool] }.join(', ')}" }

          # Remove tool call JSON from the response text (clean it up)
          cleaned_response = stream_response.dup
          tool_calls.each do |tc|
            # Remove the tool call JSON from text
            tool_json = tc.is_a?(Hash) ? tc.to_json : tc.to_s
            cleaned_response.gsub!(tool_json, '')
            cleaned_response.gsub!(/\{"name"\s*:\s*"[^"]+"\s*,\s*"parameters"\s*:\s*\{[^}]+\}\s*\}/, '')
          end
          cleaned_response.strip!

          # Add assistant message (with cleaned content)
          assistant_content = cleaned_response.strip.presence || 'I will fetch additional data to complete the analysis.'
          @messages << {
            role: 'assistant',
            content: assistant_content
          }

          # Execute tools
          tool_calls.each do |tool_call|
            tool_name = tool_call['tool'] || tool_call[:tool] || tool_call['name'] || tool_call[:name]
            tool_args = tool_call['arguments'] || tool_call[:arguments] || tool_call['parameters'] || tool_call[:parameters] || {}

            Rails.logger.info { "[Smc::AiAnalyzer] Executing tool: #{tool_name} with args: #{tool_args.inspect}" }

            tool_result = execute_tool(tool_name, tool_args)

            @messages << {
              role: 'tool',
              name: tool_name,
              content: JSON.pretty_generate(tool_result)
            }
          end

          @messages << {
            role: 'user',
            content: 'Based on the tool results above, continue your analysis. Provide a complete analysis with actionable insights for options trading.'
          }

          iteration += 1
          next
        end

        # Final response
        full_response = stream_response
        break
      end

      full_response.presence
    end

    def build_tools_definition
      [
        {
          type: 'function',
          function: {
            name: 'get_current_ltp',
            description: 'Get the current Last Traded Price (LTP) for the instrument',
            parameters: {
              type: 'object',
              properties: {},
              required: []
            }
          }
        },
        {
          type: 'function',
          function: {
            name: 'get_historical_candles',
            description: 'Get historical candle data for the instrument',
            parameters: {
              type: 'object',
              properties: {
                interval: {
                  type: 'string',
                  enum: ['5m', '15m', '1h', 'daily'],
                  description: 'Timeframe for candles'
                },
                limit: {
                  type: 'integer',
                  description: 'Number of candles to fetch (default: 50, max: 200)',
                  default: 50
                }
              },
              required: ['interval']
            }
          }
        },
        {
          type: 'function',
          function: {
            name: 'get_technical_indicators',
            description: 'Get technical indicators (RSI, MACD, ADX, Supertrend, ATR) for the instrument',
            parameters: {
              type: 'object',
              properties: {
                timeframe: {
                  type: 'string',
                  enum: ['5m', '15m', '1h', 'daily'],
                  description: 'Timeframe for indicators'
                }
              },
              required: ['timeframe']
            }
          }
        },
        {
          type: 'function',
          function: {
            name: 'get_option_chain',
            description: 'Get option chain data for the index (if applicable)',
            parameters: {
              type: 'object',
              properties: {
                expiry_date: {
                  type: 'string',
                  description: 'Expiry date in YYYY-MM-DD format (optional, defaults to nearest expiry)'
                }
              },
              required: []
            }
          }
        }
      ]
    end

    def extract_tool_calls_from_response(_response)
      # This method is no longer needed - tool_calls are extracted in execute_conversation
      # Keeping for backward compatibility
      nil
    end

    def extract_tool_calls_from_text(text)
      # Extract tool calls from text - handle multiple formats
      tool_calls = []
      seen_tools = []

      # Pattern 1: {"name": "tool_name", "parameters": {...}} (Ollama format)
      # Handle both single-line and multi-line JSON
      # Use a more lenient pattern that matches the actual format
      text.scan(/\{"name"\s*:\s*"([^"]+)"\s*,\s*"parameters"\s*:\s*(\{[^}]*\})\s*\}/) do |name, params|
        next if seen_tools.include?(name) # Avoid duplicates

        begin
          # Try to parse parameters - handle nested objects
          parsed_params = JSON.parse(params)
          tool_calls << {
            'tool' => name,
            'arguments' => parsed_params
          }
          seen_tools << name unless seen_tools.include?(name)
          Rails.logger.info { "[Smc::AiAnalyzer] Extracted tool call: #{name} with params: #{parsed_params.inspect}" }
        rescue JSON::ParserError => e
          Rails.logger.debug { "[Smc::AiAnalyzer] Failed to parse tool call params for #{name}: #{e.message}, params: #{params[0..100]}" }
        end
      end

      # Also try to find complete JSON objects that might be tool calls (more lenient)
      # Look for patterns like: {"name": "...", "parameters": {...}}
      text.scan(/\{[^}]*"name"\s*:\s*"([^"]+)"[^}]*"parameters"\s*:\s*(\{[^}]*\})[^}]*\}/) do |name, params|
        next if seen_tools.include?(name) # Avoid duplicates

        begin
          # Try to parse the full JSON object
          full_match = text.match(/\{"name"\s*:\s*"#{Regexp.escape(name)}"\s*,\s*"parameters"\s*:\s*(\{[^}]*\})\s*\}/)
          if full_match
            parsed_params = JSON.parse(full_match[1])
            tool_calls << {
              'tool' => name,
              'arguments' => parsed_params
            }
            seen_tools << name unless seen_tools.include?(name)
            Rails.logger.info { "[Smc::AiAnalyzer] Extracted tool call (lenient): #{name}" }
          end
        rescue JSON::ParserError, NoMethodError
          # Skip if can't parse
        end
      end

      # Pattern 2: {"tool": "tool_name", "arguments": {...}} (alternative format)
      text.scan(/\{"tool"\s*:\s*"([^"]+)"\s*,\s*"arguments"\s*:\s*(\{[^}]*\})\s*\}/m) do |tool, args|
        next if seen_tools.include?(tool) # Avoid duplicates

        begin
          parsed_args = JSON.parse(args)
          tool_calls << {
            'tool' => tool,
            'arguments' => parsed_args
          }
          seen_tools << tool unless seen_tools.include?(tool)
          Rails.logger.debug { "[Smc::AiAnalyzer] Extracted tool call: #{tool} with args: #{parsed_args.inspect}" }
        rescue JSON::ParserError => e
          Rails.logger.debug { "[Smc::AiAnalyzer] Failed to parse tool call args for #{tool}: #{e.message}" }
        end
      end

      # Pattern 3: Try to find complete JSON objects (more lenient parsing)
      # Look for standalone JSON objects that might be tool calls
      text.scan(/\{["']name["']\s*:\s*["']([^"']+)["']\s*,\s*["']parameters["']\s*:\s*(\{[^}]*(?:\{[^}]*\}[^}]*)*\})\s*\}/m) do |name, params|
        next if seen_tools.include?(name) # Avoid duplicates

        begin
          parsed_params = JSON.parse(params)
          tool_calls << {
            'tool' => name,
            'arguments' => parsed_params
          }
          seen_tools << name unless seen_tools.include?(name)
        rescue JSON::ParserError
          # Skip if can't parse
        end
      end

      # Pattern 4: Multiple tool calls in array format [{"name": "...", "parameters": {...}}, ...]
      array_match = text.match(/\[\s*(\{"name"\s*:\s*"[^"]+"\s*,\s*"parameters"\s*:\s*\{[^}]*\}\s*\},?\s*)+\s*\]/m)
      if array_match
        begin
          parsed = JSON.parse(array_match[0])
          parsed.each do |tc|
            tool_name = tc['name'] || tc['tool']
            next if seen_tools.include?(tool_name) # Avoid duplicates

            tool_calls << {
              'tool' => tool_name,
              'arguments' => tc['parameters'] || tc['arguments'] || {}
            }
            seen_tools << tool_name unless seen_tools.include?(tool_name)
          end
        rescue JSON::ParserError => e
          Rails.logger.debug { "[Smc::AiAnalyzer] Failed to parse tool call array: #{e.message}" }
        end
      end

      if tool_calls.any?
        Rails.logger.info { "[Smc::AiAnalyzer] Extracted #{tool_calls.size} tool call(s) from text" }
        tool_calls
      else
        nil
      end
    end

    def execute_tool(tool_name, arguments)
      # Normalize arguments (handle both string keys and symbol keys)
      args = arguments.is_a?(Hash) ? arguments : {}
      normalized_args = {}
      args.each { |k, v| normalized_args[k.to_s] = v }

      case tool_name.to_s
      when 'get_current_ltp'
        # Ignore any parameters passed (tool takes no parameters)
        get_current_ltp
      when 'get_historical_candles'
        interval = normalized_args['interval']
        unless interval
          return { error: 'interval parameter is required for get_historical_candles' }
        end
        get_historical_candles(
          interval: interval,
          limit: (normalized_args['limit'] || 50).to_i
        )
      when 'get_technical_indicators'
        timeframe = normalized_args['timeframe']
        unless timeframe
          return { error: 'timeframe parameter is required for get_technical_indicators' }
        end
        get_technical_indicators(
          timeframe: timeframe
        )
      when 'get_option_chain'
        # expiry_date is optional
        get_option_chain(
          expiry_date: normalized_args['expiry_date']
        )
      else
        { error: "Unknown tool: #{tool_name}. Available tools: get_current_ltp, get_historical_candles, get_technical_indicators, get_option_chain" }
      end
    rescue StandardError => e
      Rails.logger.error("[Smc::AiAnalyzer] Tool error (#{tool_name}): #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(3).join("\n") }
      { error: "#{e.class}: #{e.message}" }
    end

    def get_current_ltp
      ltp = @instrument.ltp || @instrument.latest_ltp
      { ltp: ltp&.to_f || 0.0, symbol: @instrument.symbol_name }
    end

    def get_historical_candles(interval:, limit:)
      series = @instrument.candles(interval: interval)
      candles = series&.candles&.last([limit, 200].min) || []

      {
        interval: interval,
        count: candles.size,
        candles: candles.map do |c|
          {
            timestamp: c.timestamp,
            open: c.open,
            high: c.high,
            low: c.low,
            close: c.close,
            volume: c.volume
          }
        end
      }
    rescue StandardError => e
      { error: "Failed to fetch candles: #{e.message}" }
    end

    def get_technical_indicators(timeframe:)
      analyzer = IndexTechnicalAnalyzer.new(@instrument.symbol_name, timeframe: timeframe)
      {
        timeframe: timeframe,
        rsi: analyzer.rsi,
        macd: analyzer.macd,
        adx: analyzer.adx,
        supertrend: analyzer.supertrend,
        atr: analyzer.atr
      }
    rescue StandardError => e
      { error: "Failed to calculate indicators: #{e.message}" }
    end

    def get_option_chain(expiry_date: nil)
      # Only for indices
      return { error: 'Option chain only available for indices' } unless @instrument.segment == 'IDX_I'

      index_key = @instrument.symbol_name
      analyzer = Options::DerivativeChainAnalyzer.new(index_key: index_key)

      expiry = expiry_date ? Date.parse(expiry_date) : analyzer.nearest_expiry
      spot = analyzer.spot_ltp
      chain = analyzer.load_chain_for_expiry(expiry, spot)

      {
        index: index_key,
        expiry: expiry.to_s,
        spot: spot,
        options: chain.first(20).map do |opt|
          {
            strike: opt[:strike],
            option_type: opt[:option_type],
            ltp: opt[:ltp],
            oi: opt[:oi],
            change: opt[:change]
          }
        end
      }
    rescue StandardError => e
      { error: "Failed to fetch option chain: #{e.message}" }
    end

    def limit_message_history(messages)
      return messages if messages.size <= MAX_MESSAGE_HISTORY

      # Keep system message and most recent messages
      system_msg = messages.first
      conversation_msgs = messages[1..-1] || []
      recent_msgs = conversation_msgs.last(MAX_MESSAGE_HISTORY - 1)

      [system_msg] + recent_msgs
    end
  end
end
