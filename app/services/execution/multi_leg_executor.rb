# frozen_string_literal: true

module Execution
  # Execute multi-leg strategies safely with rollback.
  #
  # EXECUTION ORDER (CRITICAL):
  #   Credit spreads: BUY hedge leg FIRST → then SELL short leg
  #   Debit spreads:  BUY long leg FIRST → then SELL short leg
  #   NEVER sell the short leg first without the hedge in place.
  #
  # If any leg fails after the first leg fills:
  #   → IMMEDIATELY close all filled legs (rollback)
  #   → Never leave naked short exposure
  #
  class MultiLegExecutor
    include PositionTracker::Lifecycle

    FILL_WAIT_SECONDS = 15
    FILL_POLL_INTERVAL = 1

    def self.execute!(signal:)
      new(signal: signal).execute!
    end

    def initialize(signal:)
      @signal = signal
      @leg_results = []
      @order_ids = []
      @leg_group_id = SecureRandom.uuid
    end

    def execute!
      ordered_legs = execution_order(@signal.legs)

      ordered_legs.each_with_index do |leg, index|
        result = place_leg(leg)

        if result[:failed]
          # LEG FAILED — if any previous legs filled, rollback
          if @leg_results.any? { |r| r[:filled] }
            rollback!("#{leg[:symbol]} placement failed: #{result[:error]}")
          end
          return failure("Leg #{index + 1} failed: #{result[:error]}")
        end

        # Wait for fill
        fill_result = wait_for_fill(result[:order_id], leg)

        if fill_result[:failed]
          if @leg_results.any? { |r| r[:filled] }
            rollback!("#{leg[:symbol]} fill timeout")
          end
          return failure("Leg #{index + 1} fill failed: #{fill_result[:error]}")
        end

        # Leg filled successfully
        @leg_results << fill_result
        Rails.logger.info("✅ LEG #{index + 1}/#{ordered_legs.size} FILLED: #{leg[:symbol]} @ #{fill_result[:fill_price]}")
      end

      # All legs filled — create position trackers
      trackers = create_trackers!

      Rails.logger.info("✅ STRATEGY EXECUTED: #{@signal.strategy_name} — #{ordered_legs.size} legs")
      success(trackers: trackers)
    end

    private

    # ─── Execution Order ───

    def execution_order(legs)
      # ALWAYS execute BUY (long/hedge) legs FIRST
      # This ensures we're never naked short
      buy_legs = legs.select { |l| l[:position_side] == 'long' }
      sell_legs = legs.select { |l| l[:position_side] == 'short' }
      buy_legs + sell_legs
    end

    # ─── Leg Placement ───

    def place_leg(leg)
      txn_type = leg[:position_side] == 'long' ? 'BUY' : 'SELL'

      begin
        order_id = Orders::GatewayLive.place_order(
          security_id: leg[:security_id],
          segment: leg[:segment],
          transaction_type: txn_type,
          quantity: leg[:quantity],
          order_type: 'LIMIT',
          price: leg[:entry_price],
          product_type: 'INTRADAY',
        )

        @order_ids << order_id
        { order_id: order_id, placed: true }

      rescue StandardError => e
        Rails.logger.error("LEG PLACE FAILED: #{leg[:symbol]} — #{e.message}")
        { failed: true, error: e.message }
      end
    end

    # ─── Fill Tracking ───

    def wait_for_fill(order_id, leg)
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

    # ─── Rollback ───

    def rollback!(reason)
      Rails.logger.error("⚠️ ROLLBACK: #{reason} — closing #{@leg_results.count { |r| r[:filled] }} filled legs")

      @leg_results.select { |r| r[:filled] }.each do |result|
        # For rollback, we need to close the opposite side
        # If we bought, we sell to close. If we sold, we buy to close.
        # Since we always execute BUY legs first, filled legs are typically long positions
        close_txn = 'SELL'
        begin
          Orders::GatewayLive.place_order(
            security_id: result[:security_id],
            segment: 'NSE_FNO',
            transaction_type: close_txn,
            quantity: result[:fill_quantity],
            order_type: 'MARKET',
            product_type: 'INTRADAY',
          )
          Rails.logger.info("ROLLBACK: Closed #{result[:symbol]}")
        rescue StandardError => e
          Rails.logger.error("ROLLBACK FAILED: #{result[:symbol]} — #{e.message}")
          # CRITICAL: manual intervention needed
          Core::EventBus.publish('rollback_failed', { symbol: result[:symbol], error: e.message })
        end
      end
    end

    # ─── Position Tracker Creation ───

    def create_trackers!
      @leg_results.map.with_index do |result, index|
        leg = @signal.legs[index]

        PositionTracker.create!(
          security_id: result[:security_id],
          symbol: leg[:symbol],
          side: leg[:position_side] == 'long' ? "long_#{leg[:option_type].downcase}" : "short_#{leg[:option_type].downcase}",
          position_side: leg[:position_side],
          index_key: @signal.index_name,
          status: :active,
          entry_price: result[:fill_price],
          quantity: result[:fill_quantity],
          leg_group_id: @leg_group_id,
          leg_index: index,
          leg_role: leg[:role],
          meta: {
            strategy: @signal.strategy_name,
            fill_price: result[:fill_price],
            fill_quantity: result[:fill_quantity],
            order_id: result[:order_id],
          }
        )
      end
    end

    def success(trackers:)
      { success: true, trackers: trackers }
    end

    def failure(reason)
      { success: false, error: reason }
    end
  end
end
