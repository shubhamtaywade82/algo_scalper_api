# frozen_string_literal: true

require "bigdecimal"

module Trading
  class TradingService
    MAX_POSITIONS = 3
    DEFAULT_STOP_LOSS = BigDecimal("5")
    DEFAULT_TARGET = BigDecimal("1000")

    def initialize(
      super_order_model: DhanHQ::Models::SuperOrder,
      trend_identifier: TrendIdentifier.new,
      strike_selector: StrikeSelector.new
    )
      @super_order_model = super_order_model
      @trend_identifier = trend_identifier
      @strike_selector = strike_selector
    end

    def execute_cycle!
      return unless dhanhq_enabled?
      return if global_position_limit_reached?

      Instrument.enabled.find_each do |instrument|
        process_instrument(instrument)
      end
    end

    private

    def process_instrument(instrument)
      return if active_positions_for(instrument) >= MAX_POSITIONS

      signal = @trend_identifier.signal_for(instrument)
      return unless signal == :long

      derivative = @strike_selector.select_for(instrument, signal: signal)
      return unless derivative

      return if active_positions_for_security(derivative.security_id) >= MAX_POSITIONS

      instrument.subscribe!
      Live::MarketFeedHub.instance.subscribe(segment: derivative.exchange_segment, security_id: derivative.security_id)

      order = submit_super_order(instrument, derivative)
      persist_tracker(instrument, derivative, order)
    rescue StandardError => e
      Rails.logger.error("Trading cycle failed for #{instrument.symbol_name}: #{e.class} - #{e.message}")
    end

    def submit_super_order(instrument, derivative)
      stop_loss = DEFAULT_STOP_LOSS
      target = DEFAULT_TARGET

      @super_order_model.create(
        security_id: derivative.security_id,
        exchange_segment: derivative.exchange_segment,
        transaction_type: "BUY",
        order_type: "MARKET",
        quantity: derivative.lot_size,
        product_type: "INTRADAY",
        bo_stop_loss_value: stop_loss,
        bo_profit_value: target,
        remarks: "Auto entry for #{instrument.symbol_name}"
      )
    end

    def persist_tracker(instrument, derivative, order)
      order_id =
        if order.respond_to?(:order_id)
          order.order_id
        elsif order.respond_to?(:[])
          order[:order_id] || order[:order_no]
        end

      raise "Dhan order id missing" unless order_id

      PositionTracker.create!(
        instrument: instrument,
        order_no: order_id,
        security_id: derivative.security_id,
        quantity: derivative.lot_size
      )
    end

    def active_positions_for(instrument)
      PositionTracker.active.where(instrument: instrument).count
    end

    def global_position_limit_reached?
      PositionTracker.active.count >= MAX_POSITIONS
    end

    def active_positions_for_security(security_id)
      PositionTracker.active.where(security_id: security_id).count
    end

    def dhanhq_enabled?
      config = Rails.application.config.x
      return false unless config.respond_to?(:dhanhq)

      config.dhanhq&.enabled
    end
  end
end
