# frozen_string_literal: true

require_relative '../utils/config'
require_relative '../utils/time_helpers'

module Execution
  # Enforces all risk rules before order placement
  class RiskEngine
    class RiskViolation < StandardError; end

    def initialize(position_tracker)
      @position_tracker = position_tracker
      @config = Utils::Config.config
    end

    def validate!(order, current_time: Time.now)
      validate_stop_loss!(order)
      validate_time!(current_time)
      validate_max_positions!
      validate_daily_loss!
      validate_position_size!(order)
      
      true
    end

    private

    def validate_stop_loss!(order)
      return if order.trigger_price&.positive?

      raise RiskViolation, 'Order must have a stop-loss (trigger_price)'
    end

    def validate_time!(current_time)
      unless Utils::TimeHelpers.market_open?(current_time)
        raise RiskViolation, 'Trading is only allowed during market hours'
      end

      # Disallow new orders in the first 5 minutes (09:15-09:20) and last 10 minutes (15:20-15:30)
      start_trading = build_ist_time(current_time, 9, 20)
      end_trading = build_ist_time(current_time, 15, 20)

      return if current_time >= start_trading && current_time < end_trading

      raise RiskViolation, 'Trading is only allowed between 09:20 and 15:20 IST'
    end

    def validate_max_positions!
      return if @position_tracker.open_positions.size < @config.max_positions

      raise RiskViolation, "Max open positions reached (#{@config.max_positions})"
    end

    def validate_daily_loss!
      capital = @config.capital.to_f
      max_loss = capital * (@config.max_daily_loss_pct / 100.0)
      
      return if @position_tracker.daily_pnl > -max_loss

      raise RiskViolation, 'Daily loss limit breached'
    end

    def validate_position_size!(order)
      capital = @config.capital.to_f
      max_risk_amount = capital * (@config.risk_per_trade_pct / 100.0)
      
      entry_price = order.price.positive? ? order.price : order.trigger_price * 1.05
      risk_per_unit = entry_price - order.trigger_price
      
      return unless risk_per_unit.positive?

      total_risk = risk_per_unit * order.quantity
      return if total_risk <= max_risk_amount

      raise RiskViolation, 'Position size exceeds max risk per trade'
    end

    def build_ist_time(base, hour, min, time_class = Time)
      time_class.new(base.year, base.month, base.day, hour, min, 0, '+05:30')
    end
  end
end
