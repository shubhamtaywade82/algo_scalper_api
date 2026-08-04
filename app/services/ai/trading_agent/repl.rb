# frozen_string_literal: true

require 'readline'

module Ai
  module TradingAgent
    # Interactive REPL for the trading agent.
    # Supports natural language queries and slash commands.
    # rubocop:disable Rails/Output
    class Repl
      COMMANDS = {
        '/trade' => 'Analyze and trade: /trade <symbol> [timeframe]',
        '/positions' => 'Show active positions',
        '/funds' => 'Show account funds',
        '/stats' => 'Show trading stats for today',
        '/clear' => 'Clear conversation history',
        '/switch' => 'Switch LLM model: /switch <model>',
        '/help' => 'Show this help',
        '/quit' => 'Exit the agent'
      }.freeze

      MODEL_STATE_FILE = Rails.root.join("tmp/.last_model")
      HISTORY_FILE = Rails.root.join("tmp/.agent_history")

      def initialize(model: nil)
        @client = Services::Ai::OllamaClient.instance
        @model = model || load_saved_model || 'gpt-oss:20b-cloud'
        @running = false
        @conversation = load_history
        @loop = AgentLoop.new(model: @model)
      end

      def start
        puts '=' * 60
        puts 'Trading Agent — DhanHQ Interactive REPL'
        puts "Model: #{@model}"
        puts "Type /help for commands, or ask anything about the market."
        puts '=' * 60
        puts

        @running = true

        while @running
          input = Readline.readline('trading-agent> ', true)
          break if input.nil? # EOF

          input = input.strip
          next if input.empty?

          handle_input(input)
        end

        puts "\nGoodbye."
      end

      private

      def handle_input(input)
        if input.start_with?('/')
          handle_command(input)
        else
          handle_query(input)
        end
      rescue Interrupt
        puts "\n[Interrupted]"
      rescue StandardError => e
        puts "Error: #{e.class} — #{e.message}"
        Rails.logger.error("[TradingAgent::Repl] Error: #{e.class} — #{e.message}") if defined?(Rails)
      end

      def handle_command(input)
        parts = input.split(' ', 2)
        cmd = parts[0].downcase
        arg = parts[1]&.strip

        case cmd
        when '/quit', '/exit'
          @running = false
        when '/help'
          show_help
        when '/clear'
          @conversation.clear
          FileUtils.rm_f(HISTORY_FILE)
          puts 'Conversation cleared.'
        when '/trade'
          handle_trade(arg)
        when '/positions'
          show_positions
        when '/funds'
          show_funds
        when '/stats'
          show_stats
        when '/switch'
          switch_model(arg)
        else
          puts "Unknown command: #{cmd}. Type /help for available commands."
        end
      end

      def handle_trade(arg)
        if arg.blank?
          puts 'Usage: /trade <symbol> [timeframe]'
          puts 'Example: /trade NIFTY 15m'
          puts 'Example: /trade BANKNIFTY'
          return
        end

        parts = arg.split(' ', 2)
        symbol = parts[0].upcase
        timeframe = parts[1] || '15m'

        puts "\nAnalyzing #{symbol} (#{timeframe})..."
        puts

        result = @loop.run(symbol: symbol, timeframe: timeframe) do |chunk|
          print Ai::TradingAgent::TerminalMarkdown.render(chunk)
        end

        puts
        puts

        if result
          puts "Action: #{result[:action] || 'ANALYSIS'}"
          puts "Confidence: #{((result[:confidence] || 0) * 100).round(1)}%"
        end
      end

      def handle_query(query)
        puts

        @conversation = @loop.run_query(query: query, conversation: @conversation) do |chunk|
          print Ai::TradingAgent::TerminalMarkdown.render(chunk)
        end

        save_history
        puts
        puts
      end

      def show_help
        puts "\nAvailable commands:"
        COMMANDS.each { |cmd, desc| puts "  #{cmd.ljust(12)} — #{desc}" }
        puts
        puts "Natural language: Just type your question about the market."
        puts "Example: 'Analyze NIFTY' or 'What is the trend for BANKNIFTY?'"
        puts
      end

      def show_positions
        puts "\nFetching positions..."
        result = Ai::DhanToolBridge.call('portfolio.positions')
        if result.is_a?(Hash) && result['portfolio.positions']
          positions = result['portfolio.positions']
          if positions.is_a?(Array) && positions.any?
            positions.each do |p|
              puts "  #{p[:trading_symbol] || p['trading_symbol']} — " \
                   "Qty: #{p[:net_qty] || p['net_qty']} — " \
                   "Avg: #{p[:avg_price] || p['avg_price']}"
            end
          else
            puts '  No active positions.'
          end
        else
          puts "  Error fetching positions: #{result}"
        end
      end

      def show_funds
        puts "\nFetching funds..."
        result = Ai::DhanToolBridge.call('portfolio.funds')
        if result.is_a?(Hash) && result['portfolio.funds']
          funds = result['portfolio.funds']
          puts "  Available: ₹#{funds[:available_cash] || funds['available_cash']}"
          puts "  Used: ₹#{funds[:used_margin] || funds['used_margin']}"
          puts "  Total: ₹#{funds[:total_margin] || funds['total_margin']}"
        else
          puts "  Error fetching funds: #{result}"
        end
      end

      def show_stats
        stats = Ai::TradingAgent::ToolRegistry.execute('get_trading_stats', {})
        if stats.is_a?(Hash) && !stats[:error]
          puts "\nTrading Stats (#{stats[:date]}):"
          puts "  Total Trades: #{stats[:total_trades]}"
          puts "  Winners: #{stats[:winners]}"
          puts "  Losers: #{stats[:losers]}"
          puts "  Win Rate: #{stats[:win_rate]}%"
          puts "  Realized P&L: ₹#{stats[:realized_pnl]}"
        else
          puts "  Error: #{stats[:error] || 'Unknown error'}"
        end
      end

      def switch_model(model_name)
        if model_name.blank?
          puts "Current model: #{@model}"
          puts "Usage: /switch <model_name>"
          return
        end

        @model = model_name
        @loop.model = model_name
        save_model(model_name)
        puts "Switched to model: #{model_name}"
      end

      def load_saved_model
        File.read(MODEL_STATE_FILE).strip
      rescue StandardError
        nil
      end

      def save_model(model_name)
        File.write(MODEL_STATE_FILE, model_name)
      rescue StandardError
        # ignore — not critical
      end

      def load_history
        data = File.read(HISTORY_FILE)
        JSON.parse(data, symbolize_names: true)
      rescue StandardError
        []
      end

      def save_history
        # Keep last 3 exchanges (6 messages) — too much history causes stale data reuse
        trimmed = @conversation.last(6)
        File.write(HISTORY_FILE, trimmed.to_json)
      rescue StandardError
        # ignore
      end
    end
    # rubocop:enable Rails/Output
  end
end
