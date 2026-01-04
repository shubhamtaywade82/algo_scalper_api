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

    def execute_conversation_stream(&block)
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
          Rails.logger.debug { "[Smc::AiAnalyzer] Tool calls in stream: #{tool_calls.map { |tc| tc['tool'] }.join(', ')}" }

          # Add assistant message
          @messages << {
            role: 'assistant',
            content: stream_response
          }

          # Execute tools
          tool_calls.each do |tool_call|
            tool_name = tool_call['tool']
            tool_args = tool_call['arguments'] || {}

            Rails.logger.debug { "[Smc::AiAnalyzer] Executing tool: #{tool_name}" }

            tool_result = execute_tool(tool_name, tool_args)

            @messages << {
              role: 'tool',
              name: tool_name,
              content: JSON.pretty_generate(tool_result)
            }
          end

          @messages << {
            role: 'user',
            content: 'Continue your analysis based on the tool results.'
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

    def extract_tool_calls_from_response(response)
      # This method is no longer needed - tool_calls are extracted in execute_conversation
      # Keeping for backward compatibility
      nil
    end

    def extract_tool_calls_from_text(text)
      # Fallback: extract tool calls from text (for streaming or non-native tool calling)
      json_match = text.match(/\{"tool"\s*:\s*"([^"]+)"\s*,\s*"arguments"\s*:\s*(\{.*?\})\s*\}/m)
      return nil unless json_match

      begin
        [{
          'tool' => json_match[1],
          'arguments' => JSON.parse(json_match[2])
        }]
      rescue JSON::ParserError
        nil
      end
    end

    def execute_tool(tool_name, arguments)
      case tool_name
      when 'get_current_ltp'
        get_current_ltp
      when 'get_historical_candles'
        get_historical_candles(
          interval: arguments['interval'] || arguments[:interval],
          limit: (arguments['limit'] || arguments[:limit] || 50).to_i
        )
      when 'get_technical_indicators'
        get_technical_indicators(
          timeframe: arguments['timeframe'] || arguments[:timeframe]
        )
      when 'get_option_chain'
        get_option_chain(
          expiry_date: arguments['expiry_date'] || arguments[:expiry_date]
        )
      else
        { error: "Unknown tool: #{tool_name}" }
      end
    rescue StandardError => e
      Rails.logger.error("[Smc::AiAnalyzer] Tool error (#{tool_name}): #{e.class} - #{e.message}")
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
