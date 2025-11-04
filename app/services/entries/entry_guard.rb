# frozen_string_literal: true

module Entries
  class EntryGuard
    class << self
      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1)
        instrument = find_instrument(index_cfg)
        return false unless instrument

        multiplier = [scale_multiplier.to_i, 1].max
        # Rails.logger.info("[EntryGuard] Scale multiplier for #{index_cfg[:key]}: x#{multiplier}") if multiplier > 1

        side = direction == :bullish ? 'long_ce' : 'long_pe'
        return false unless exposure_ok?(instrument: instrument, side: side, max_same_side: index_cfg[:max_same_side])
        return false if cooldown_active?(pick[:symbol], index_cfg[:cooldown_sec].to_i)

        # Never block due to WebSocket - always allow REST API fallback
        # Log WebSocket status for monitoring but don't block
        hub = Live::MarketFeedHub.instance
        unless hub.running? && hub.connected?
          # Rails.logger.info('[EntryGuard] WebSocket not connected - will use REST API fallback for LTP')
        end

        # Rails.logger.debug { "[EntryGuard] Pick data: #{pick.inspect}" }
        # Resolve LTP with REST API fallback if WebSocket unavailable
        ltp = pick[:ltp]
        if ltp.blank? || needs_api_ltp?(pick)
          # Fetch fresh LTP from REST API when WS unavailable or pick LTP is stale
          resolved_ltp = resolve_entry_ltp(instrument: instrument, pick: pick, index_cfg: index_cfg)
          ltp = resolved_ltp if resolved_ltp.present?
        end

        return false unless ltp.present? && ltp.to_f.positive?

        quantity = Capital::Allocator.qty_for(
          index_cfg: index_cfg,
          entry_price: ltp.to_f,
          derivative_lot_size: pick[:lot_size],
          scale_multiplier: multiplier
        )
        return false if quantity <= 0

        response = Orders.config.place_market(
          side: 'buy',
          segment: pick[:segment] || index_cfg[:segment],
          security_id: pick[:security_id],
          qty: quantity,
          meta: {
            client_order_id: build_client_order_id(index_cfg: index_cfg, pick: pick),
            ltp: ltp # Pass resolved LTP (from WS or API)
          }
        )

        order_no = extract_order_no(response)
        return false unless order_no

        create_tracker!(
          instrument: instrument,
          order_no: order_no,
          pick: pick,
          side: side,
          quantity: quantity,
          index_cfg: index_cfg,
          ltp: ltp
        )

        Rails.logger.info("[EntryGuard] Successfully placed order #{order_no} for #{index_cfg[:key]}: #{pick[:symbol]}")
        true
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

        # Rails.logger.info("[Pyramiding] Allowing second position - first position profitable: #{first_position.last_pnl_rupees}")
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

      # Checks if we need to fetch LTP from REST API
      # @param pick [Hash] Pick data from signal
      # @return [Boolean]
      def needs_api_ltp?(pick)
        hub = Live::MarketFeedHub.instance
        return true unless hub.running? && hub.connected?

        # If pick LTP is missing or zero, we need API fallback
        pick[:ltp].blank? || pick[:ltp].to_f.zero?
      end

      # Resolves LTP for entry order, with REST API fallback
      # @param instrument [Instrument]
      # @param pick [Hash] Pick data from signal
      # @param index_cfg [Hash] Index configuration
      # @return [BigDecimal, nil]
      def resolve_entry_ltp(instrument:, pick:, index_cfg:)
        segment = pick[:segment] || index_cfg[:segment]
        security_id = pick[:security_id]

        return nil unless segment.present? && security_id.present?

        # Try to resolve via instrument/derivative object
        if pick[:derivative_id].present?
          derivative = Derivative.find_by(id: pick[:derivative_id])
          if derivative
            api_ltp = derivative.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
            return BigDecimal(api_ltp.to_s) if api_ltp.present?
          end
        end

        # Fallback to instrument method
        api_ltp = instrument.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
        return BigDecimal(api_ltp.to_s) if api_ltp.present?

        Rails.logger.warn("[EntryGuard] Failed to resolve LTP from API for #{segment}:#{security_id}")
        nil
      rescue StandardError => e
        Rails.logger.error("[EntryGuard] Error resolving entry LTP: #{e.class} - #{e.message}")
        nil
      end

      private

      # Removed ensure_ws_connection! - no longer needed
      # WebSocket status is checked inline in try_enter for logging only
      # REST API fallback is always used when WS unavailable

      def find_instrument(index_cfg)
        segment_code = index_cfg[:segment]
        instrument = Instrument.find_by_sid_and_segment(
          security_id: index_cfg[:sid],
          segment_code: segment_code,
          symbol_name: index_cfg[:key]
        )

        unless instrument
          # Rails.logger.warn(
          #   "[EntryGuard] Instrument lookup failed for #{index_cfg[:key]} (segment: #{segment_code}, sid: #{index_cfg[:sid]})"
          # )
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
        elsif response.respond_to?(:[]) # Struct-like (e.g., OpenStruct)
          response[:order_id] || response[:order_no] || response.order_id
        end
      end

      def create_tracker!(instrument:, order_no:, pick:, side:, quantity:, index_cfg:, ltp:)
        PositionTracker.create!(
          instrument: instrument,
          order_no: order_no,
          security_id: pick[:security_id].to_s,
          symbol: pick[:symbol],
          segment: pick[:segment] || index_cfg[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp,
          meta: { index_key: index_cfg[:key], direction: side, placed_at: Time.current }
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to persist tracker for order #{order_no}: #{e.record.errors.full_messages.to_sentence}")
      end
    end
  end
end
