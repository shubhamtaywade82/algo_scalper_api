# frozen_string_literal: true

# rubocop:disable-next Rails/Output
module Ai
  module TradingBot
    # SMC event scanner for the trading bot.
    # Uses existing SMC engines with DhanHQ candle data.
    class Scanner
      def initialize(config)
        @config = config
      end

      # Scans for SMC events on a symbol.
      # Returns array of event hashes.
      def scan(symbol)
        events = []

        @config.timeframes.each_value do |interval|
          series = fetch_candles(symbol, interval)
          next unless series&.candles&.any?

          smc_context = Smc::Context.new(series)
          tf_events = extract_events(smc_context, symbol, interval)
          events.concat(tf_events)
        rescue StandardError => e
          puts "  Scanner error for #{symbol} @ #{interval}: #{e.message}" if @config.verbose?
        end

        events
      end

      private

      def fetch_candles(symbol, interval)
        instrument = find_instrument(symbol)
        return nil unless instrument

        ensure_dhanhq_error_handler
        instrument.candles(interval: interval.to_s)
      end

      def find_instrument(symbol)
        # Try NSE FNO first for indices, then NSE EQ
        Instrument.find_by(symbol_name: symbol, segment: 'index') ||
          Instrument.find_by(underlying_symbol: symbol, segment: 'index') ||
          Instrument.find_by(underlying_symbol: symbol, segment: 'equity')
      end

      def extract_events(smc_context, symbol, interval)
        events = []

        # Check for BOS/CHoCH
        structure = smc_context.internal_structure
        if structure
          trend = structure[:trend] || structure['trend']
          events << {
            type: 'structure_break',
            symbol: symbol,
            interval: interval,
            trend: trend,
            timestamp: Time.current
          } if trend && trend != :range
        end

        # Check for liquidity sweeps
        liquidity = smc_context.liquidity
        if liquidity
          buy_side = liquidity[:buy_side_taken] || liquidity['buy_side_taken']
          sell_side = liquidity[:sell_side_taken] || liquidity['sell_side_taken']

          if buy_side
            events << {
              type: 'liquidity_sweep',
              symbol: symbol,
              interval: interval,
              direction: 'buy_side',
              timestamp: Time.current
            }
          end

          if sell_side
            events << {
              type: 'liquidity_sweep',
              symbol: symbol,
              interval: interval,
              direction: 'sell_side',
              timestamp: Time.current
            }
          end
        end

        # Check for active order blocks
        order_blocks = smc_context.order_blocks
        if order_blocks.is_a?(Array)
          active_obs = order_blocks.select { |ob| !ob[:mitigated] && !ob['mitigated'] }
          active_obs.each do |ob|
            direction = ob[:direction] || ob['direction']
            events << {
              type: 'order_block',
              symbol: symbol,
              interval: interval,
              direction: direction,
              zone: ob[:zone] || ob['zone'],
              timestamp: Time.current
            }
          end
        end

        events
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
