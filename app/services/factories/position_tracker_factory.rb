# frozen_string_literal: true

module Factories
  # Factory for creating PositionTracker instances
  # Centralizes position tracker creation logic for paper and live trading
  class PositionTrackerFactory
    class << self
      # Create a paper trading position tracker
      # @param instrument [Instrument] Instrument instance
      # @param pick [Hash] Pick data with :security_id, :symbol, :segment, :derivative_id
      # @param side [String] Position side ('long_ce', 'long_pe')
      # @param quantity [Integer] Position quantity
      # @param index_cfg [Hash] Index configuration
      # @param ltp [BigDecimal, Float] Last traded price
      # @return [PositionTracker] Created tracker instance
      def create_paper_tracker(instrument:, pick:, side:, quantity:, index_cfg:, ltp:)
        order_no = generate_paper_order_no(index_cfg: index_cfg, pick: pick)
        watchable = resolve_watchable(pick: pick, instrument: instrument)

        tracker = PositionTracker.create!(
          watchable: watchable,
          instrument: resolve_instrument(watchable: watchable),
          order_no: order_no,
          security_id: pick[:security_id].to_s,
          symbol: pick[:symbol],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp,
          avg_price: ltp,
          status: :active,
          paper: true,
          meta: build_paper_meta(index_cfg: index_cfg, side: side)
        )

        initialize_paper_tracker_post_creation(tracker: tracker, ltp: ltp)
        tracker
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("[Factories::PositionTrackerFactory] Failed to create paper tracker: #{e.record.errors.full_messages.to_sentence}")
        raise
      end

      # Create a live trading position tracker
      # @param instrument [Instrument] Instrument instance
      # @param order_no [String] Order number from broker
      # @param pick [Hash] Pick data
      # @param side [String] Position side
      # @param quantity [Integer] Position quantity
      # @param index_cfg [Hash] Index configuration
      # @param ltp [BigDecimal, Float] Last traded price
      # @return [PositionTracker] Created or averaged tracker instance
      def create_live_tracker(instrument:, order_no:, pick:, side:, quantity:, index_cfg:, ltp:)
        watchable = resolve_watchable(pick: pick, instrument: instrument)

        PositionTracker.build_or_average!(
          watchable: watchable,
          instrument: resolve_instrument(watchable: watchable),
          order_no: order_no,
          security_id: pick[:security_id].to_s,
          symbol: pick[:symbol],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp,
          meta: build_live_meta(index_cfg: index_cfg, side: side)
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("[Factories::PositionTrackerFactory] Failed to create live tracker: #{e.record.errors.full_messages.to_sentence}")
        raise
      end

      # Create tracker with averaging logic
      # Finds existing active tracker and averages, or creates new one
      # @param attributes [Hash] Tracker attributes
      # @return [PositionTracker] Created or updated tracker
      def build_or_average(attributes)
        segment = attributes[:segment].to_s
        security_id = attributes[:security_id].to_s

        active_tracker = PositionTracker.active.find_by(
          segment: segment,
          security_id: security_id
        )

        if active_tracker
          average_position(tracker: active_tracker, new_quantity: attributes[:quantity], new_price: attributes[:entry_price])
        else
          create_new_tracker(attributes)
        end
      end

      private

      def generate_paper_order_no(index_cfg:, pick:)
        "PAPER-#{index_cfg[:key]}-#{pick[:security_id]}-#{Time.current.to_i}"
      end

      def resolve_watchable(pick:, instrument:)
        # Try derivative_id first
        if pick[:derivative_id].present?
          derivative = Derivative.find_by(id: pick[:derivative_id])
          return derivative if derivative
        end

        # Try to find derivative by security_id and segment
        segment = pick[:segment] || instrument.exchange_segment
        if segment.present? && pick[:security_id].present?
          derivative = Derivative.find_by(
            security_id: pick[:security_id].to_s,
            exchange: instrument.exchange,
            segment: segment
          )
          return derivative if derivative
        end

        # Fallback to instrument
        instrument
      end

      def resolve_instrument(watchable:)
        watchable.is_a?(Derivative) ? watchable.instrument : watchable
      end

      def build_paper_meta(index_cfg:, side:)
        {
          index_key: index_cfg[:key],
          direction: side,
          placed_at: Time.current,
          paper_trading: true
        }
      end

      def build_live_meta(index_cfg:, side:)
        {
          index_key: index_cfg[:key],
          direction: side,
          placed_at: Time.current
        }
      end

      def initialize_paper_tracker_post_creation(tracker:, ltp:)
        # Initialize PnL in Redis
        initial_pnl = BigDecimal(0)
        Live::RedisPnlCache.instance.store_pnl(
          tracker_id: tracker.id,
          pnl: initial_pnl,
          pnl_pct: 0.0,
          ltp: ltp,
          hwm: initial_pnl,
          hwm_pnl_pct: 0.0,
          timestamp: Time.current,
          tracker: tracker
        )

        # Add to ActiveCache with default SL/TP
        risk_cfg = AlgoConfig.fetch.dig(:risk) || {}
        sl_pct = risk_cfg[:sl_pct] || 0.30
        tp_pct = risk_cfg[:tp_pct] || 0.60

        sl_price = (ltp.to_f * (1 - sl_pct)).round(2)
        tp_price = (ltp.to_f * (1 + tp_pct)).round(2)

        Positions::ActiveCache.instance.add_position(
          tracker: tracker,
          sl_price: sl_price,
          tp_price: tp_price
        )
      rescue StandardError => e
        Rails.logger.error("[Factories::PositionTrackerFactory] Post-creation initialization failed: #{e.class} - #{e.message}")
      end

      def average_position(tracker:, new_quantity:, new_price:)
        old_qty = tracker.quantity.to_i
        new_qty = old_qty + new_quantity.to_i

        new_avg = (
          (tracker.entry_price.to_f * old_qty) +
          (new_price.to_f * new_quantity.to_i)
        ) / new_qty

        tracker.update!(
          quantity: new_qty,
          entry_price: new_avg.round(2),
          avg_price: new_avg.round(2)
        )

        tracker
      end

      def create_new_tracker(attributes)
        PositionTracker.create!(
          watchable: attributes[:watchable],
          instrument: attributes[:instrument],
          order_no: attributes[:order_no],
          security_id: attributes[:security_id].to_s,
          symbol: attributes[:symbol],
          segment: attributes[:segment].to_s,
          side: attributes[:side],
          quantity: attributes[:quantity],
          entry_price: attributes[:entry_price],
          avg_price: attributes[:entry_price],
          status: :active,
          meta: attributes[:meta] || {}
        )
      end
    end
  end
end
