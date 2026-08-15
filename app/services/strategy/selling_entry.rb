# frozen_string_literal: true

module Strategy
  # Options selling entry service
  # Handles entry for short option positions and multi-leg strategies
  #
  class SellingEntry
    def self.execute!(index_cfg:, signal:)
      new(index_cfg: index_cfg, signal: signal).execute!
    end

    def initialize(index_cfg:, signal:)
      @index_cfg = index_cfg
      @signal = signal
    end

    def execute!
      # Check margin before placing any orders
      margin_check = Risk::MarginEngine.check!(
        signal: @signal,
        available_margin: Capital::Allocator.available_margin
      )

      unless margin_check[:allowed]
        Rails.logger.warn("[SellingEntry] Margin check failed: #{margin_check[:reason]}")
        return { success: false, error: margin_check[:reason] }
      end

      # For multi-leg strategies, use MultiLegExecutor
      if multi_leg_strategy?
        Execution::MultiLegExecutor.execute!(signal: @signal)
      else
        # Single leg short position
        place_single_leg
      end
    end

    private

    def multi_leg_strategy?
      @signal.legs.is_a?(Array) && @signal.legs.size > 1
    end

    def place_single_leg
      leg = @signal.legs.first

      begin
        order_id = Orders::GatewayLive.place_order(
          security_id: leg[:security_id],
          segment: leg[:segment],
          transaction_type: 'SELL',
          quantity: leg[:quantity],
          order_type: 'LIMIT',
          price: leg[:entry_price],
          product_type: 'INTRADAY',
        )

        # Wait for fill
        fill_result = wait_for_fill(order_id, leg)

        if fill_result[:failed]
          return { success: false, error: fill_result[:error] }
        end

        # Create position tracker
        tracker = PositionTracker.create!(
          security_id: fill_result[:security_id],
          symbol: leg[:symbol],
          side: "short_#{leg[:option_type].downcase}",
          position_side: 'short',
          index_key: @index_cfg[:key],
          status: :active,
          entry_price: fill_result[:fill_price],
          quantity: fill_result[:fill_quantity],
          premium_received: fill_result[:fill_price] * fill_result[:fill_quantity],
          margin_required: leg[:margin_required],
          meta: {
            strategy: @signal.strategy_name,
            fill_price: fill_result[:fill_price],
            fill_quantity: fill_result[:fill_quantity],
            order_id: order_id,
          }
        )

        Rails.logger.info("✅ SELLING ENTRY: #{leg[:symbol]} @ #{fill_result[:fill_price]}")
        { success: true, tracker: tracker }

      rescue StandardError => e
        Rails.logger.error("[SellingEntry] Order placement failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    def wait_for_fill(order_id, leg)
      FILL_WAIT_SECONDS = 15
      FILL_POLL_INTERVAL = 1
      elapsed = 0

      while elapsed < FILL_WAIT_SECONDS
        status = Orders::GatewayLive.order_status(order_id)
        order_status = status[:orderStatus]

        case order_status
        when 'TRADED'
          return {
            filled: true,
            order_id: order_id,
            fill_price: status[:tradedPrice].to_f,
            fill_quantity: status[:tradedQty].to_i,
            security_id: leg[:security_id],
            symbol: leg[:symbol],
          }
        when 'REJECTED', 'CANCELLED'
          return { failed: true, error: "Order #{order_status}" }
        end

        sleep(FILL_POLL_INTERVAL)
        elapsed += FILL_POLL_INTERVAL
      end

      # Timeout — cancel the order
      begin
        Orders::GatewayLive.cancel_order(order_id)
      rescue StandardError
        nil
      end

      { failed: true, error: "Fill timeout after #{FILL_WAIT_SECONDS}s" }
    end
  end
end
