# frozen_string_literal: true

# rubocop:disable Rails/Output
module Ai
  module TradingBot
    # Main trading bot engine.
    # Polling loop: scan for events -> analyze with LLM -> execute trades -> manage positions.
    class Engine
      def initialize(config)
        @config = config
        @scanner = Scanner.new(config)
        @analyst = Analyst.new(config)
        @trader = Trader.new(config)
        @notifier = Notifier.new(config)
        @self_learning = SelfLearning.new(config)
        @running = false
        @symbol_states = {}
      end

      def run
        @running = true
        puts '=' * 60
        puts "TradingBot Engine — #{@config.mode.upcase} mode"
        puts "Symbols: #{@config.symbols.join(', ')}"
        puts "Poll: #{@config.poll_interval_sec}s | Model: #{@config.model || 'auto'}"
        puts '=' * 60

        @config.symbols.each do |symbol|
          @symbol_states[symbol] = { last_event_time: nil, last_analysis_time: 0 }
        end

        while @running
          begin
            tick
            sleep @config.poll_interval_sec
          rescue Interrupt
            puts "\nShutting down..."
            @running = false
          rescue StandardError => e
            puts "Engine error: #{e.message}"
            puts e.backtrace.first(3).join("\n") if @config.verbose?
            sleep 5
          end
        end
      end

      def stop
        @running = false
      end

      private

      def tick
        now = Time.now.to_f

        @config.symbols.each do |symbol|
          state = @symbol_states[symbol] || {}
          open_trades = @trader.open_trades_count(symbol)
          total_open = @trader.total_open_trades

          # Scan for SMC events
          events = @scanner.scan(symbol)

          # Analyze if events detected or periodic check
          should_analyze = events.any? || time_for_periodic?(symbol, now)

          if should_analyze && can_analyze?(symbol, now, open_trades, total_open)
            perform_analysis(symbol, events)
            state[:last_analysis_time] = now
          end

          # Check exits for open positions
          @trader.check_exits(symbol)

          @symbol_states[symbol] = state
        end
      end

      def perform_analysis(symbol, events)
        puts "\n[#{Time.now.strftime('%H:%M:%S')}] Analyzing #{symbol}..."

        signal = @analyst.analyze(symbol, events: events)
        return unless signal

        if signal[:action] && %w[BUY SELL].include?(signal[:action])
          result = @trader.execute(signal)
          log_execution(symbol, signal, result)
          @notifier.notify_signal(symbol, signal, result) if @config.telegram_notify
        else
          puts "  #{symbol}: No trade (#{signal[:action]})"
        end
      end

      def log_execution(symbol, signal, result)
        if result[:success]
          puts "  #{symbol}: #{signal[:action]} executed — #{result[:type]} " \
               "entry=#{result[:entry]} qty=#{result[:qty]}"
        else
          puts "  #{symbol}: Execution failed — #{result[:reason]}"
        end
      end

      def time_for_periodic?(symbol, now)
        state = @symbol_states[symbol] || {}
        last = state[:last_analysis_time] || 0
        (now - last) >= @config.poll_interval_sec * 3
      end

      def can_analyze?(symbol, now, open_trades, total_open)
        return false if open_trades >= @config.max_setups_per_symbol
        return false if total_open >= @config.max_open_trades

        state = @symbol_states[symbol] || {}
        last = state[:last_analysis_time] || 0
        (now - last) >= @config.poll_interval_sec
      end
    end
  end
end
# rubocop:enable Rails/Output
