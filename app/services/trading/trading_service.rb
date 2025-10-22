# frozen_string_literal: true

module Trading
  class TradingService
    MAX_POSITIONS = 3

    def initialize(
      order_model: DhanHQ::Models::Order,
      trend_identifier: TrendIdentifier.new,
      strike_selector: StrikeSelector.new
    )
      @order_model = order_model
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
      derivative.subscribe

      order = submit_market_order(instrument, derivative)
      persist_tracker(instrument, derivative, order)
    rescue StandardError => e
      Rails.logger.error("Trading cycle failed for #{instrument.symbol_name}: #{e.class} - #{e.message}")
    end

    def submit_market_order(instrument, derivative)
      @order_model.create(
        security_id: derivative.security_id,
        exchange_segment: derivative.exchange_segment,
        transaction_type: "BUY",
        order_type: "MARKET",
        quantity: derivative.lot_size,
        product_type: "INTRADAY",
        validity: "DAY",
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
      # Always enabled - just check for credentials
      client_id = ENV["DHANHQ_CLIENT_ID"].presence || ENV["CLIENT_ID"].presence
      access    = ENV["DHANHQ_ACCESS_TOKEN"].presence || ENV["ACCESS_TOKEN"].presence
      client_id.present? && access.present?
    end
  end
end
