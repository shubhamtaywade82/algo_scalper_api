# frozen_string_literal: true

module Risk
  module Rules
    # Context object that provides all necessary data for rule evaluation
    # This encapsulates position data, tracker, config, and other context
    class RuleContext
      attr_reader :position, :tracker, :risk_config, :current_time, :trading_session

      def initialize(position:, tracker:, risk_config: {}, current_time: nil, trading_session: nil)
        @position = position
        @tracker = tracker
        @risk_config = risk_config || {}
        @current_time = current_time || Time.current
        @trading_session = trading_session
      end

      # Get PnL percentage from position
      # @return [Float, nil] PnL percentage or nil if not available
      def pnl_pct
        position.pnl_pct
      end

      # Get PnL in rupees from position
      # @return [Float, nil] PnL in rupees or nil if not available
      def pnl_rupees
        position.pnl
      end

      # Get high water mark from position
      # @return [Float, nil] High water mark or nil if not available
      def high_water_mark
        position.high_water_mark
      end

      # Get peak profit percentage from position
      # @return [Float, nil] Peak profit percentage or nil if not available
      def peak_profit_pct
        position.peak_profit_pct
      end

      # Get current LTP from position
      # @return [BigDecimal, nil] Current LTP or nil if not available
      def current_ltp
        position.current_ltp
      end

      # Get entry price from tracker
      # @return [BigDecimal, nil] Entry price or nil if not available
      def entry_price
        tracker.entry_price
      end

      # Get quantity from tracker
      # @return [Integer, nil] Quantity or nil if not available
      def quantity
        tracker.quantity
      end

      # Check if position is active
      # @return [Boolean] true if active, false otherwise
      def active?
        tracker&.active? && position
      end

      # Get a config value with optional default
      # @param key [Symbol, String] Config key
      # @param default [Object] Default value if key not found
      # @return [Object] Config value or default
      def config_value(key, default = nil)
        risk_config[key.to_sym] || risk_config[key.to_s] || default
      end

      # Get a BigDecimal config value
      # @param key [Symbol, String] Config key
      # @param default [BigDecimal] Default value if key not found
      # @return [BigDecimal] Config value as BigDecimal
      def config_bigdecimal(key, default = BigDecimal('0'))
        value = config_value(key, default)
        BigDecimal(value.to_s)
      rescue StandardError
        default
      end

      # Get a time config value (parsed from HH:MM format)
      # @param key [Symbol, String] Config key
      # @param default [Time, nil] Default value if key not found
      # @return [Time, nil] Parsed time or nil
      def config_time(key, default = nil)
        value = config_value(key)
        return default unless value

        Time.zone.parse(value.to_s)
      rescue StandardError
        default
      end
    end
  end
end
