# frozen_string_literal: true

# rubocop:disable Rails/Output
module Ai
  module TradingBot
    # LLM-powered trade analyst.
    # Sends market context to Ollama and parses structured trade signals.
    class Analyst
      def initialize(config)
        @config = config
        @client = Services::Ai::OllamaClient.instance
      end

      # Analyzes a symbol with detected events and returns a trade signal.
      # @param symbol [String] e.g., "NIFTY"
      # @param events [Array<Hash>] detected SMC events
      # @return [Hash] trade signal with :action, :entry_price, :stop_loss, etc.
      def analyze(symbol, events: [])
        context = build_context(symbol, events)
        signal = query_llm(context)
        validate_signal(signal, symbol)
      end

      private

      def build_context(symbol, events)
        # Fetch current market data via DhanHQ
        ltp = fetch_ltp(symbol)
        indicators = fetch_indicators(symbol)

        {
          symbol: symbol,
          ltp: ltp,
          events: events.map { |e| "#{e[:type]} (#{e[:interval]}) #{e[:direction] || ''}" },
          indicators: indicators,
          timestamp: Time.current.iso8601
        }
      end

      def fetch_ltp(symbol)
        instrument = find_instrument(symbol)
        return nil unless instrument

        ensure_dhanhq_error_handler
        instrument.ltp
      rescue StandardError
        nil
      end

      def fetch_indicators(symbol)
        instrument = find_instrument(symbol)
        return {} unless instrument

        ensure_dhanhq_error_handler
        series = instrument.candles(interval: '15')
        return {} unless series&.candles&.any?

        {
          rsi: series.rsi(14)&.round(2),
          macd: series.macd(12, 26, 9),
          adx: series.adx(14)&.round(2),
          supertrend: series.supertrend_signal,
          atr: series.atr(14)&.round(2)
        }
      rescue StandardError
        {}
      end

      def find_instrument(symbol)
        Instrument.find_by(symbol_name: symbol, segment: 'index') ||
          Instrument.find_by(underlying_symbol: symbol, segment: 'index') ||
          Instrument.find_by(underlying_symbol: symbol, segment: 'equity')
      end

      def query_llm(context)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user', content: build_user_prompt(context) }
        ]

        response = @client.chat(
          messages: messages,
          model: @config.model,
          temperature: 0.2
        )

        parse_response(response)
      end

      def system_prompt
        <<~PROMPT
          You are an automated trading signal generator for Indian markets.
          Analyze the provided market context and output a JSON trade signal.

          OUTPUT FORMAT (strict JSON):
          {
            "action": "BUY" | "SELL" | "HOLD",
            "confidence": 0.0 to 1.0,
            "entry_price": <number>,
            "stop_loss": <number>,
            "take_profit": <number>,
            "risk_percent": <number, max 2.0>,
            "reason": "<brief reason>"
          }

          RULES:
          - Only output valid JSON, no other text
          - R:R ratio must be at least 1.5
          - Risk per trade must not exceed 2%
          - HOLD if conditions are unclear
          - Consider SMC events (BOS/CHoCH, liquidity sweeps, order blocks)
        PROMPT
      end

      def build_user_prompt(context)
        lines = []
        lines << "Symbol: #{context[:symbol]}"
        lines << "LTP: #{context[:ltp]}" if context[:ltp]
        lines << "Events: #{context[:events].join(', ')}" if context[:events].any?

        if context[:indicators].any?
          ind = context[:indicators]
          lines << "RSI(14): #{ind[:rsi]}" if ind[:rsi]
          lines << "ADX(14): #{ind[:adx]}" if ind[:adx]
          lines << "Supertrend: #{ind[:supertrend]}" if ind[:supertrend]
          lines << "ATR(14): #{ind[:atr]}" if ind[:atr]
        end

        lines << "Time: #{context[:timestamp]}"
        lines.join("\n")
      end

      def parse_response(response)
        return { action: 'HOLD', confidence: 0 } unless response.is_a?(String)

        # Extract JSON from response
        json_match = response.match(/\{[^{}]*\}/)
        return { action: 'HOLD', confidence: 0 } unless json_match

        parsed = JSON.parse(json_match[0])
        {
          action: parsed['action']&.upcase,
          confidence: parsed['confidence']&.to_f || 0.5,
          entry_price: parsed['entry_price']&.to_f,
          stop_loss: parsed['stop_loss']&.to_f,
          take_profit: parsed['take_profit']&.to_f,
          risk_percent: parsed['risk_percent']&.to_f || 1.0,
          reason: parsed['reason']
        }
      rescue JSON::ParserError
        { action: 'HOLD', confidence: 0 }
      end

      def validate_signal(signal, symbol)
        # Basic validation
        return signal if signal[:action] == 'HOLD'

        # Must have entry, SL, TP
        unless signal[:entry_price] && signal[:stop_loss] && signal[:take_profit]
          puts "  #{symbol}: Invalid signal (missing levels), holding."
          return { action: 'HOLD', confidence: 0 }
        end

        # Check R:R
        risk = (signal[:entry_price] - signal[:stop_loss]).abs
        reward = (signal[:take_profit] - signal[:entry_price]).abs
        rr = risk.positive? ? reward / risk : 0

        if rr < 1.5
          puts "  #{symbol}: R:R too low (#{rr.round(2)}), holding."
          return { action: 'HOLD', confidence: 0 }
        end

        signal[:rr_ratio] = rr.round(2)
        signal
      end

      def ensure_dhanhq_error_handler
        return unless defined?(Rails)
        return if defined?(DhanhqErrorHandler) && DhanhqErrorHandler.respond_to?(:handle_dhanhq_error)

        file_path = Rails.root.join('app/services/concerns/dhanhq_error_handler.rb')
        require file_path.to_s if File.exist?(file_path)
      end
    end
  end
end
# rubocop:enable Rails/Output
