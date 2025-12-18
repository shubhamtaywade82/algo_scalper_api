# frozen_string_literal: true

module Services
  module Ai
    # AI-powered trading analysis service
    # Uses OpenAI to analyze trading patterns, suggest improvements, etc.
    class TradingAnalyzer
      class << self
        def analyze_trading_day(date: Time.zone.today, stream: false, &)
          new.analyze_trading_day(date: date, stream: stream, &)
        end

        def suggest_strategy_improvements(performance_data:, stream: false, &)
          new.suggest_strategy_improvements(performance_data: performance_data, stream: stream, &)
        end

        def analyze_market_conditions(market_data:, stream: false, &)
          new.analyze_market_conditions(market_data: market_data, stream: stream, &)
        end
      end

      def initialize
        @client = Services::Ai::OpenaiClient.instance
      end

      def analyze_trading_day(date: Time.zone.today, stream: false, &block)
        return nil unless @client.enabled?

        stats = PositionTracker.paper_trading_stats_with_pct(date: date)
        positions = PositionTracker.paper
                                   .where('created_at >= ?', date.beginning_of_day)
                                   .exited
                                   .order(:exited_at)
                                   .limit(50) # Limit for token efficiency

        prompt = build_analysis_prompt(stats: stats, positions: positions, date: date)

        pp prompt
        # Auto-select model (will use best available for Ollama)
        model = if @client.provider == :ollama
                  @client.selected_model || ENV['OLLAMA_MODEL'] || 'llama3'
                else
                  'gpt-4o'
                end

        if stream && block_given?
          full_response = +''
          begin
            @client.chat_stream(
              messages: [
                { role: 'system', content: system_prompt },
                { role: 'user', content: prompt }
              ],
              model: model,
              temperature: 0.3
            ) do |chunk|
              if chunk.present?
                full_response << chunk
                yield(chunk)
              end
            end
          rescue Faraday::TimeoutError, Net::ReadTimeout => e
            # Timeout during streaming - return partial response if we got content
            Rails.logger.warn { "[TradingAnalyzer] Stream timeout: #{e.message}" }
            if full_response.present?
              Rails.logger.info { "[TradingAnalyzer] Returning partial response (#{full_response.length} chars)" }
            end
          rescue StandardError => e
            # Stream may end with connection errors - this is often expected
            if e.message.include?('end of file') || e.message.include?('Connection') || e.message.include?('closed')
              Rails.logger.debug { "[TradingAnalyzer] Stream completed normally: #{e.class}" } if Rails.env.development?
            else
              Rails.logger.warn { "[TradingAnalyzer] Stream error: #{e.class} - #{e.message}" }
            end
          end
          parse_analysis_response(full_response) if full_response.present?
        else
          response = @client.chat(
            messages: [
              { role: 'system', content: system_prompt },
              { role: 'user', content: prompt }
            ],
            model: model,
            temperature: 0.3
          )
          parse_analysis_response(response)
        end
      rescue StandardError => e
        Rails.logger.error("[TradingAnalyzer] Analysis error: #{e.class} - #{e.message}")
        nil
      end

      def suggest_strategy_improvements(performance_data:, stream: false, &block)
        return nil unless @client.enabled?

        prompt = build_strategy_prompt(performance_data: performance_data)
        # Auto-select model (will use best available for Ollama)
        model = if @client.provider == :ollama
                  @client.selected_model || ENV['OLLAMA_MODEL'] || 'llama3'
                else
                  'gpt-4o'
                end

        if stream && block_given?
          full_response = +''
          begin
            @client.chat_stream(
              messages: [
                { role: 'system', content: strategy_system_prompt },
                { role: 'user', content: prompt }
              ],
              model: model,
              temperature: 0.4
            ) do |chunk|
              if chunk.present?
                full_response << chunk
                yield(chunk)
              end
            end
          rescue Faraday::TimeoutError, Net::ReadTimeout => e
            # Timeout during streaming - return partial response if we got content
            Rails.logger.warn { "[TradingAnalyzer] Stream timeout: #{e.message}" }
            if full_response.present?
              Rails.logger.info { "[TradingAnalyzer] Returning partial response (#{full_response.length} chars)" }
            end
          rescue StandardError => e
            # Stream may end with connection errors - this is often expected
            if e.message.include?('end of file') || e.message.include?('Connection') || e.message.include?('closed')
              Rails.logger.debug { "[TradingAnalyzer] Stream completed normally: #{e.class}" } if Rails.env.development?
            else
              Rails.logger.warn { "[TradingAnalyzer] Stream error: #{e.class} - #{e.message}" }
            end
          end
          parse_strategy_response(full_response) if full_response.present?
        else
          response = @client.chat(
            messages: [
              { role: 'system', content: strategy_system_prompt },
              { role: 'user', content: prompt }
            ],
            model: model,
            temperature: 0.4
          )
          parse_strategy_response(response)
        end
      rescue StandardError => e
        Rails.logger.error("[TradingAnalyzer] Strategy suggestion error: #{e.class} - #{e.message}")
        nil
      end

      def analyze_market_conditions(market_data:, stream: false, &block)
        return nil unless @client.enabled?

        prompt = build_market_analysis_prompt(market_data: market_data)
        # Auto-select model (will use best available for Ollama)
        model = if @client.provider == :ollama
                  @client.selected_model || ENV['OLLAMA_MODEL'] || 'llama3'
                else
                  'gpt-4o'
                end

        if stream && block_given?
          full_response = +''
          begin
            @client.chat_stream(
              messages: [
                { role: 'system', content: market_system_prompt },
                { role: 'user', content: prompt }
              ],
              model: model,
              temperature: 0.3
            ) do |chunk|
              if chunk.present?
                full_response << chunk
                yield(chunk)
              end
            end
          rescue Faraday::TimeoutError, Net::ReadTimeout => e
            # Timeout during streaming - return partial response if we got content
            Rails.logger.warn { "[TradingAnalyzer] Stream timeout: #{e.message}" }
            if full_response.present?
              Rails.logger.info { "[TradingAnalyzer] Returning partial response (#{full_response.length} chars)" }
            end
          rescue StandardError => e
            # Stream may end with connection errors - this is often expected
            if e.message.include?('end of file') || e.message.include?('Connection') || e.message.include?('closed')
              Rails.logger.debug { "[TradingAnalyzer] Stream completed normally: #{e.class}" } if Rails.env.development?
            else
              Rails.logger.warn { "[TradingAnalyzer] Stream error: #{e.class} - #{e.message}" }
            end
          end
          parse_market_response(full_response) if full_response.present?
        else
          response = @client.chat(
            messages: [
              { role: 'system', content: market_system_prompt },
              { role: 'user', content: prompt }
            ],
            model: model,
            temperature: 0.3
          )
          parse_market_response(response)
        end
      rescue StandardError => e
        Rails.logger.error("[TradingAnalyzer] Market analysis error: #{e.class} - #{e.message}")
        nil
      end

      private

      def system_prompt
        <<~PROMPT
          You are an expert algorithmic trading analyst specializing in Indian index options trading (NIFTY, BANKNIFTY, SENSEX).
          Analyze trading performance data and provide actionable insights.
          Focus on:
          - Win rate patterns
          - Profit/loss distribution
          - Time-based performance
          - Entry/exit timing
          - Risk management effectiveness
          Provide concise, data-driven recommendations.
        PROMPT
      end

      def strategy_system_prompt
        <<~PROMPT
          You are a quantitative trading strategy consultant.
          Analyze trading performance and suggest specific, actionable improvements to trading strategies.
          Consider:
          - Entry signal optimization
          - Exit rule refinement
          - Position sizing adjustments
          - Risk management enhancements
          Provide concrete recommendations with reasoning.
        PROMPT
      end

      def market_system_prompt
        <<~PROMPT
          You are a market analyst specializing in Indian equity derivatives.
          Analyze market conditions and provide insights on:
          - Volatility patterns
          - Trend strength
          - Market regime identification
          - Trading opportunity assessment
          Provide clear, actionable market analysis.
        PROMPT
      end

      def build_analysis_prompt(stats:, positions:, date:)
        position_summary = positions.map do |p|
          {
            symbol: p.symbol,
            entry: p.entry_price,
            exit: p.exit_price,
            pnl: p.last_pnl_rupees,
            pnl_pct: (p.last_pnl_pct || 0) * 100,
            exit_reason: p.exit_reason,
            entry_time: p.created_at.strftime('%H:%M:%S'),
            exit_time: p.exited_at&.strftime('%H:%M:%S')
          }
        end

        <<~PROMPT
          Analyze trading performance for #{date.strftime('%Y-%m-%d')}:

          Overall Statistics:
          - Total Trades: #{stats[:total_trades]}
          - Winners: #{stats[:winners]} | Losers: #{stats[:losers]}
          - Win Rate: #{stats[:win_rate] || 0}%
          - Realized PnL: ₹#{stats[:realized_pnl_rupees] || 0}
          - Realized PnL %: #{stats[:realized_pnl_pct] || 0}%

          Recent Trades (last #{positions.count}):
          #{JSON.pretty_generate(position_summary)}

          Provide:
          1. Key performance insights
          2. Patterns identified
          3. Areas for improvement
          4. Specific recommendations
        PROMPT
      end

      def build_strategy_prompt(performance_data:)
        <<~PROMPT
          Analyze this trading performance data and suggest strategy improvements:

          #{JSON.pretty_generate(performance_data)}

          Provide:
          1. Top 3 strategy improvements
          2. Specific parameter adjustments
          3. Risk management enhancements
          4. Entry/exit rule optimizations
        PROMPT
      end

      def build_market_analysis_prompt(market_data:)
        <<~PROMPT
          Analyze current market conditions:

          #{JSON.pretty_generate(market_data)}

          Provide:
          1. Market regime assessment
          2. Volatility outlook
          3. Trading opportunity assessment
          4. Risk factors
        PROMPT
      end

      def parse_analysis_response(response)
        {
          analysis: response,
          generated_at: Time.current,
          provider: @client.provider
        }
      end

      def parse_strategy_response(response)
        {
          suggestions: response,
          generated_at: Time.current,
          provider: @client.provider
        }
      end

      def parse_market_response(response)
        {
          analysis: response,
          generated_at: Time.current,
          provider: @client.provider
        }
      end
    end
  end
end
