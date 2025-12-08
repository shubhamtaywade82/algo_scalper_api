# frozen_string_literal: true

module Repositories
  # Repository for PositionTracker data access
  # Abstracts database queries and provides clean interface
  class PositionTrackerRepository
    class << self
      # Find active tracker by segment and security ID
      # @param segment [String] Exchange segment
      # @param security_id [String] Security ID
      # @return [PositionTracker, nil]
      def find_active_by_segment_and_security(segment:, security_id:)
        PositionTracker.active.find_by(segment: segment.to_s, security_id: security_id.to_s)
      end

      # Find tracker by order number
      # @param order_no [String] Order number
      # @return [PositionTracker, nil]
      def find_by_order_no(order_no)
        PositionTracker.find_by(order_no: order_no.to_s)
      end

      # Count active positions by side
      # @param side [String] Position side ('long_ce', 'long_pe', etc.)
      # @return [Integer]
      def active_count_by_side(side:)
        PositionTracker.active.where(side: side.to_s).count
      end

      # Find active positions for an instrument
      # @param instrument [Instrument] Instrument instance
      # @return [ActiveRecord::Relation]
      def find_active_by_instrument(instrument)
        PositionTracker.active.where(instrument_id: instrument.id)
      end

      # Find active positions by index key
      # @param index_key [String] Index key (e.g., 'NIFTY', 'BANKNIFTY')
      # @return [ActiveRecord::Relation]
      def find_active_by_index_key(index_key)
        PositionTracker.active.where("meta->>'index_key' = ?", index_key.to_s)
      end

      # Find positions by status
      # @param status [Symbol, String] Status (:active, :exited, :pending, :cancelled)
      # @return [ActiveRecord::Relation]
      def find_by_status(status)
        PositionTracker.where(status: status.to_s)
      end

      # Find paper trading positions
      # @return [ActiveRecord::Relation]
      def find_paper_positions
        PositionTracker.paper
      end

      # Find live trading positions
      # @return [ActiveRecord::Relation]
      def find_live_positions
        PositionTracker.live
      end

      # Find exited positions for an instrument
      # @param instrument [Instrument] Instrument instance
      # @return [ActiveRecord::Relation]
      def find_exited_by_instrument(instrument)
        PositionTracker.exited.where(instrument_id: instrument.id)
      end

      # Check if position exists for segment and security
      # @param segment [String] Exchange segment
      # @param security_id [String] Security ID
      # @return [Boolean]
      def exists_for_segment_and_security?(segment:, security_id:)
        PositionTracker.exists?(segment: segment.to_s, security_id: security_id.to_s, status: :active)
      end

      # Get active positions count
      # @return [Integer]
      def active_count
        PositionTracker.active.count
      end

      # Get positions with PnL above threshold
      # @param threshold [BigDecimal, Float] PnL threshold
      # @return [ActiveRecord::Relation]
      def find_profitable_above(threshold)
        PositionTracker.active.where('last_pnl_rupees > ?', threshold.to_f)
      end

      # Get positions with PnL below threshold (losses)
      # @param threshold [BigDecimal, Float] PnL threshold (negative)
      # @return [ActiveRecord::Relation]
      def find_losses_below(threshold)
        PositionTracker.active.where('last_pnl_rupees < ?', threshold.to_f)
      end

      # Find positions by date range
      # @param start_date [Date, Time] Start date
      # @param end_date [Date, Time] End date
      # @return [ActiveRecord::Relation]
      def find_by_date_range(start_date:, end_date:)
        PositionTracker.where(created_at: start_date..end_date)
      end

      # Get statistics for positions
      # @param scope [ActiveRecord::Relation, nil] Optional scope to filter
      # @return [Hash] Statistics hash
      def statistics(scope: nil)
        positions = scope || PositionTracker.all

        {
          total: positions.count,
          active: positions.active.count,
          exited: positions.exited.count,
          cancelled: positions.cancelled.count,
          paper: positions.paper.count,
          live: positions.live.count,
          total_pnl: positions.sum { |p| p.last_pnl_rupees.to_f },
          avg_pnl: positions.average(:last_pnl_rupees)&.to_f || 0.0
        }
      end
    end
  end
end
