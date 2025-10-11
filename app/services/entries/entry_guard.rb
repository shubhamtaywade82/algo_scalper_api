# frozen_string_literal: true

module Entries
  class EntryGuard
    class << self
      def try_enter(index_cfg:, pick:, direction:)
        instrument = find_instrument(index_cfg)
        return unless instrument

        side = direction == :bullish ? "long_ce" : "long_pe"
        return unless exposure_ok?(instrument: instrument, side: side, max_same_side: index_cfg[:max_same_side])
        return if cooldown_active?(pick[:symbol], index_cfg[:cooldown_sec].to_i)

        quantity = Capital::Allocator.qty_for(index_cfg: index_cfg, entry_price: pick[:ltp].to_f)
        return if quantity <= 0

        response = Orders::Placer.buy_market!(
          seg: pick[:segment] || index_cfg[:segment],
          sid: pick[:security_id],
          qty: quantity,
          client_order_id: build_client_order_id(index_cfg: index_cfg, pick: pick)
        )

        order_no = extract_order_no(response)
        return unless order_no

        create_tracker!(
          instrument: instrument,
          order_no: order_no,
          pick: pick,
          side: side,
          quantity: quantity,
          index_cfg: index_cfg
        )
      rescue StandardError => e
        Rails.logger.error("EntryGuard failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
      end

      def exposure_ok?(instrument:, side:, max_same_side:)
        PositionTracker.where(instrument: instrument, side: side, status: PositionTracker::STATUSES[:active]).count <
          max_same_side.to_i
      end

      def cooldown_active?(symbol, cooldown)
        return false if symbol.blank? || cooldown <= 0

        last = Rails.cache.read("reentry:#{symbol}")
        last.present? && (Time.current - last) < cooldown
      end

      private

      def find_instrument(index_cfg)
        Instrument.find_by(security_id: index_cfg[:sid]) || Instrument.find_by(symbol_name: index_cfg[:key].to_s)
      end

      def build_client_order_id(index_cfg:, pick:)
        "AS-#{index_cfg[:key]}-#{pick[:security_id]}-#{Time.current.to_i}"
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
