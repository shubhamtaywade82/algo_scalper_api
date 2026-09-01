# frozen_string_literal: true

# rubocop:disable-next Rails/Output
module Ai
  module TradingBot
    # Trade execution layer.
    # Supports paper and live (DhanHQ) execution via existing Gateway pattern.
    class Trader
      def initialize(config)
        @config = config
        @gateway = build_gateway
      end

      # Executes a trade signal.
      # @param signal [Hash] trade signal from Analyst
      # @return [Hash] execution result
      def execute(signal)
        if @config.paper?
          paper_execute(signal)
        else
          live_execute(signal)
        end
      end

      # Checks exits for open positions on a symbol.
      def check_exits(symbol)
        positions = @gateway.open_positions
        return unless positions.is_a?(Array)

        positions.each do |pos|
          next unless match_symbol?(pos, symbol)

          check_single_exit(pos)
        end
      end

      # Count open trades for a symbol.
      def open_trades_count(symbol)
        positions = @gateway.open_positions
        return 0 unless positions.is_a?(Array)

        positions.count { |p| match_symbol?(p, symbol) }
      end

      # Count total open trades.
      def total_open_trades
        positions = @gateway.open_positions
        return 0 unless positions.is_a?(Array)

        positions.size
      end

      private

      def build_gateway
        if @config.paper?
          Orders::GatewayPaper.new
        else
          Orders::GatewayLive.new
        end
      end

      def paper_execute(signal)
        entry = apply_slippage(signal[:entry_price], signal[:action] == 'BUY')
        sl = signal[:stop_loss]
        qty = compute_quantity(entry, sl, signal[:action])

        result = @gateway.place_market(
          symbol: signal[:symbol],
          action: signal[:action],
          quantity: qty,
          price: entry
        )

        if result[:success]
          {
            success: true,
            type: 'paper',
            entry: entry.round(2),
            qty: qty,
            sl: sl.round(2),
            tp: signal[:take_profit]&.round(2),
            risk_pct: signal[:risk_percent]
          }
        else
          { success: false, reason: result[:error] || 'Paper execution failed' }
        end
      rescue StandardError => e
        { success: false, reason: "Paper execution error: #{e.message}" }
      end

      def live_execute(signal)
        entry = apply_slippage(signal[:entry_price], signal[:action] == 'BUY')
        sl = signal[:stop_loss]
        qty = compute_quantity(entry, sl, signal[:action])

        result = @gateway.place_market(
          symbol: signal[:symbol],
          action: signal[:action],
          quantity: qty,
          price: entry
        )

        if result[:success]
          {
            success: true,
            type: 'live',
            entry: entry.round(2),
            qty: qty,
            sl: sl.round(2),
            tp: signal[:take_profit]&.round(2),
            risk_pct: signal[:risk_percent],
            order_id: result[:order_id]
          }
        else
          { success: false, reason: result[:error] || 'Live execution failed' }
        end
      rescue StandardError => e
        { success: false, reason: "Live execution error: #{e.message}" }
      end

      def check_single_exit(position)
        current_price = fetch_current_price(position[:symbol])
        return unless current_price

        direction = position[:side]&.upcase
        entry = position[:entry_price]&.to_f
        sl = position[:stop_loss]&.to_f
        tp = position[:take_profit]&.to_f

        # Break-even trigger
        if tp && direction == 'BUY' && current_price >= tp && sl < entry
          update_stop_loss(position, entry)
        end

        # Stop loss hit
        if direction == 'BUY' && current_price <= sl
          close_position(position, current_price, 'stop_loss')
        elsif direction == 'SELL' && current_price >= sl
          close_position(position, current_price, 'stop_loss')
        end

        # Take profit hit
        if tp
          if direction == 'BUY' && current_price >= tp
            close_position(position, current_price, 'take_profit')
          elsif direction == 'SELL' && current_price <= tp
            close_position(position, current_price, 'take_profit')
          end
        end
      end

      def close_position(position, exit_price, reason)
        @gateway.exit_position(position[:id])
        puts "  Position closed: #{position[:symbol]} @ #{exit_price} (#{reason})"
      rescue StandardError => e
        puts "  Error closing position: #{e.message}"
      end

      def update_stop_loss(position, new_sl)
        @gateway.modify_order(position[:id], stop_loss: new_sl)
        puts "  SL moved to break-even for #{position[:symbol]}"
      rescue StandardError => e
        puts "  Error updating SL: #{e.message}"
      end

      def fetch_current_price(symbol)
        instrument = find_instrument(symbol)
        return nil unless instrument

        ensure_dhanhq_error_handler
        instrument.ltp&.to_f
      rescue StandardError
        nil
      end

      def find_instrument(symbol)
        Instrument.find_by(symbol_name: symbol, segment: 'index') ||
          Instrument.find_by(underlying_symbol: symbol, segment: 'index') ||
          Instrument.find_by(underlying_symbol: symbol, segment: 'equity')
      end

      def match_symbol?(position, symbol)
        pos_symbol = position[:symbol] || position[:trading_symbol]
        pos_symbol&.upcase == symbol.upcase
      end

      def apply_slippage(price, is_buy)
        slippage = @config.slippage_pct / 100.0
        is_buy ? price * (1 + slippage) : price * (1 - slippage)
      end

      def compute_quantity(entry, sl, action)
        risk_per_trade = @config.initial_balance * (@config.max_risk_per_trade_pct / 100.0)
        risk_per_unit = (entry - sl).abs
        return 1 if risk_per_unit.zero?

        (risk_per_trade / risk_per_unit).floor
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
