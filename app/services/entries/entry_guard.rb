# frozen_string_literal: true

module Entries
  class EntryGuard
    class << self
      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1)
        instrument = find_instrument(index_cfg)
        return false unless instrument

        multiplier = [scale_multiplier.to_i, 1].max
        Rails.logger.info("[EntryGuard] Scale multiplier for #{index_cfg[:key]}: x#{multiplier}") if multiplier > 1

        side = direction == :bullish ? 'long_ce' : 'long_pe'
        return false unless exposure_ok?(instrument: instrument, side: side, max_same_side: index_cfg[:max_same_side])
        return false if cooldown_active?(pick[:symbol], index_cfg[:cooldown_sec].to_i)

        ensure_ws_connection!

        Rails.logger.debug { "[EntryGuard] Pick data: #{pick.inspect}" }
        quantity = Capital::Allocator.qty_for(
          index_cfg: index_cfg,
          entry_price: pick[:ltp].to_f,
          derivative_lot_size: pick[:lot_size],
          scale_multiplier: multiplier
        )
        return false if quantity <= 0

        response = Orders::Placer.buy_market!(
          seg: pick[:segment] || index_cfg[:segment],
          sid: pick[:security_id],
          qty: quantity,
          client_order_id: build_client_order_id(index_cfg: index_cfg, pick: pick)
        )

        order_no = extract_order_no(response)
        return false unless order_no

        create_tracker!(
          instrument: instrument,
          order_no: order_no,
          pick: pick,
          side: side,
          quantity: quantity,
          index_cfg: index_cfg
        )

        Rails.logger.info("[EntryGuard] Successfully placed order #{order_no} for #{index_cfg[:key]}: #{pick[:symbol]}")
        true
      rescue Live::FeedHealthService::FeedStaleError => e
        Rails.logger.warn("[EntryGuard] Blocked entry for #{index_cfg[:key]}: #{e.message}")
        false
      rescue StandardError => e
        Rails.logger.error("EntryGuard failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
        false
      end

      def exposure_ok?(instrument:, side:, max_same_side:)
        # Use efficient query with index
        active_positions = PositionTracker.where(
          instrument: instrument,
          side: side,
          status: PositionTracker::STATUSES[:active]
        ).limit(max_same_side.to_i + 1) # Only fetch what we need
        current_count = active_positions.count

        # Check if we've reached the maximum allowed positions
        return false if current_count >= max_same_side.to_i

        # If this would be the second position, check pyramiding rules
        return pyramiding_allowed?(active_positions.first) if current_count == 1

        true
      end

      def pyramiding_allowed?(first_position)
        # Second position only allowed if first position is profitable
        return false unless first_position.last_pnl_rupees&.positive?

        # Additional check: ensure first position has been profitable for at least 5 minutes
        # to avoid premature pyramiding
        min_profit_duration = 5.minutes
        return false unless first_position.updated_at < min_profit_duration.ago

        Rails.logger.info("[Pyramiding] Allowing second position - first position profitable: #{first_position.last_pnl_rupees}")
        true
      rescue StandardError => e
        Rails.logger.error("Pyramiding check failed: #{e.message}")
        false
      end

      def cooldown_active?(symbol, cooldown)
        return false if symbol.blank? || cooldown <= 0

        last = Rails.cache.read("reentry:#{symbol}")
        last.present? && (Time.current - last) < cooldown
      end

      private

      def ensure_ws_connection!
        # Only check if WebSocket is connected, skip ticks staleness
        unless Live::MarketFeedHub.instance.running?
          Rails.logger.warn('[EntryGuard] Blocked entry: WebSocket market feed not running')
          raise Live::FeedHealthService::FeedStaleError.new(
            feed: :ws_connection,
            last_seen_at: nil,
            threshold: 0,
            last_error: nil
          )
        end

        # Check funds and positions health (but skip ticks staleness)
        Live::FeedHealthService.instance.assert_healthy!(%i[funds positions])
      end

      def ensure_feed_health!
        Live::FeedHealthService.instance.assert_healthy!(%i[funds positions ticks])
      end

      def find_instrument(index_cfg)
        segment_code = index_cfg[:segment]
        instrument = Instrument.find_by_sid_and_segment(
          security_id: index_cfg[:sid],
          segment_code: segment_code,
          symbol_name: index_cfg[:key]
        )

        unless instrument
          Rails.logger.warn(
            "[EntryGuard] Instrument lookup failed for #{index_cfg[:key]} (segment: #{segment_code}, sid: #{index_cfg[:sid]})"
          )
        end

        instrument
      end

      def build_client_order_id(index_cfg:, pick:)
        # DhanHQ correlation_id limit is 25 characters
        # Format: AS-{KEY}-{SID}-{TIMESTAMP}
        # Keep it under 25 chars by using shorter timestamp
        timestamp = Time.current.to_i.to_s[-6..] # Last 6 digits of timestamp
        "AS-#{index_cfg[:key][0..3]}-#{pick[:security_id]}-#{timestamp}"
      end

      def extract_order_no(response)
        return if response.blank?

        if response.respond_to?(:order_id)
          response.order_id
        elsif response.is_a?(Hash)
          response[:order_id] || response[:order_no]
        elsif response.respond_to?(:[]) # Struct-like
          response[:order_id] || response[:order_no]
        end
      end

      def create_tracker!(instrument:, order_no:, pick:, side:, quantity:, index_cfg:)
        PositionTracker.create!(
          instrument: instrument,
          order_no: order_no,
          security_id: pick[:security_id].to_s,
          symbol: pick[:symbol],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: pick[:ltp],
          meta: { index_key: index_cfg[:key], direction: side, placed_at: Time.current }
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to persist tracker for order #{order_no}: #{e.record.errors.full_messages.to_sentence}")
      end
    end
  end
end
