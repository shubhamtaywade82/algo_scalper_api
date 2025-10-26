# frozen_string_literal: true

require 'singleton'

module Live
  class PositionSyncService
    include Singleton

    def initialize
      @last_sync = nil
      @sync_interval = 30.seconds
    end

    def sync_positions!
      return unless should_sync?

      Rails.logger.info('[PositionSync] Starting position synchronization')

      begin
        # Fetch all active positions from DhanHQ
        dhan_positions = DhanHQ::Models::Position.active
        Rails.logger.info("[PositionSync] Found #{dhan_positions.size} active positions in DhanHQ")

        # Get all tracked positions from database with proper preloading
        tracked_positions = PositionTracker.active.eager_load(:instrument).to_a
        tracked_security_ids = tracked_positions.map { |p| p.security_id.to_s } # rubocop:disable Performance/MapMethodChain

        Rails.logger.info("[PositionSync] Found #{tracked_positions.size} tracked positions in database")

        # Find positions that exist in DhanHQ but not in our database
        untracked_positions = []

        dhan_positions.each do |dhan_pos|
          security_id = extract_security_id(dhan_pos)
          next unless security_id

          unless tracked_security_ids.include?(security_id.to_s)
            untracked_positions << dhan_pos
            Rails.logger.warn("[PositionSync] Found untracked position: #{security_id} - #{extract_symbol(dhan_pos)}")
          end
        end

        # Create PositionTracker records for untracked positions
        untracked_positions.each do |dhan_pos|
          create_tracker_for_position(dhan_pos)
        end

        # Check for positions that exist in database but not in DhanHQ (should be marked as exited)
        orphaned_trackers = tracked_positions.reject do |tracker|
          dhan_positions.any? { |dp| extract_security_id(dp).to_s == tracker.security_id.to_s }
        end

        orphaned_trackers.each do |tracker|
          Rails.logger.warn("[PositionSync] Found orphaned tracker: #{tracker.order_no} - marking as exited")
          tracker.mark_exited!
        end

        @last_sync = Time.current
        Rails.logger.info("[PositionSync] Synchronization completed - created #{untracked_positions.size} trackers, marked #{orphaned_trackers.size} as exited")
      rescue StandardError => e
        Rails.logger.error("[PositionSync] Failed to sync positions: #{e.class} - #{e.message}")
        Rails.logger.error("[PositionSync] Backtrace: #{e.backtrace.first(5).join(', ')}")
      end
    end

    def force_sync!
      @last_sync = nil
      sync_positions!
    end

    private

    def should_sync?
      @last_sync.nil? || (Time.current - @last_sync) >= @sync_interval
    end

    def extract_security_id(dhan_position)
      dhan_position.security_id
    end

    def extract_symbol(dhan_position)
      dhan_position.trading_symbol
    end

    def extract_exchange_segment(dhan_position)
      dhan_position.exchange_segment
    end

    def extract_quantity(dhan_position)
      dhan_position.net_qty || 0
    end

    def extract_average_price(dhan_position)
      # Use buy_avg as the average price
      dhan_position.buy_avg
    end

    def parse_exchange_segment(exchange_segment)
      # Parse exchange_segment like "NSE_FNO" into ["nse", "derivatives"]
      # DhanHQ uses "NSE_FNO" but our database uses "nse" and "derivatives"
      case exchange_segment
      when 'NSE_FNO'
        %w[nse derivatives]
      when 'BSE_FNO'
        %w[bse derivatives]
      when 'NSE_EQ'
        %w[nse equity]
      when 'BSE_EQ'
        %w[bse equity]
      else
        # Fallback - try to parse as exchange_segment
        if exchange_segment&.include?('_')
          parts = exchange_segment.split('_', 2)
          [parts[0].downcase, parts[1].downcase]
        else
          ['nse', exchange_segment&.downcase]
        end
      end
    end

    def create_tracker_for_position(dhan_position)
      security_id = extract_security_id(dhan_position)
      symbol = extract_symbol(dhan_position)
      exchange_segment = extract_exchange_segment(dhan_position)
      quantity = extract_quantity(dhan_position)
      average_price = extract_average_price(dhan_position)

      # Find the derivative (for options) or instrument (for indices)
      # Parse exchange_segment (e.g., "NSE_FNO" -> exchange: "NSE", segment: "FNO")
      exchange, segment = parse_exchange_segment(exchange_segment)

      # For options (derivatives), look up derivatives
      if segment == 'derivatives'
        derivative = Derivative.find_by(
          security_id: security_id,
          exchange: exchange,
          segment: segment
        )

        unless derivative
          Rails.logger.error("[PositionSync] Could not find derivative for #{security_id} (#{exchange_segment})")
          return
        end

        instrument = derivative.instrument
      else
        # For indices, look up instruments directly
        instrument = Instrument.find_by(
          security_id: security_id,
          exchange: exchange,
          segment: segment
        )

        unless instrument
          Rails.logger.error("[PositionSync] Could not find instrument for #{security_id} (#{exchange_segment})")
          return
        end
      end

      # Generate a synthetic order number for untracked positions
      synthetic_order_no = "SYNC-#{security_id}-#{Time.current.to_i}"

      # Create PositionTracker
      tracker = PositionTracker.create!(
        instrument: instrument,
        order_no: synthetic_order_no,
        security_id: security_id.to_s,
        symbol: symbol,
        segment: exchange_segment,
        side: 'long', # Default assumption - could be enhanced to detect actual side
        status: PositionTracker::STATUSES[:active],
        quantity: quantity,
        avg_price: average_price,
        entry_price: average_price,
        meta: {
          synced_from_dhan: true,
          sync_timestamp: Time.current,
          original_position_data: begin
            dhan_position.to_h
          rescue StandardError
            {}
          end
        }
      )

      # Subscribe to market feed
      tracker.subscribe

      Rails.logger.info("[PositionSync] Created tracker #{tracker.id} for untracked position #{security_id}")
    rescue StandardError => e
      Rails.logger.error("[PositionSync] Failed to create tracker for position #{security_id}: #{e.class} - #{e.message}")
    end
  end
end
