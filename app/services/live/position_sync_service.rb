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

      if paper_trading_enabled?
        sync_paper_positions
      else
        sync_live_positions
      end

      PositionTracker.clear_orphaned_redis_pnl!
    end

    def force_sync!
      @last_sync = nil
      sync_positions!
    end

    private

    def should_sync?
      @last_sync.nil? || (Time.current - @last_sync) >= @sync_interval
    end

    def sync_live_positions
      # Rails.logger.info('[PositionSync] Starting live position synchronization')

      # Fetch all active positions from DhanHQ
      dhan_positions = DhanHQ::Models::Position.active
      # Rails.logger.info("[PositionSync] Found #{dhan_positions.size} active positions in DhanHQ")

      # Get all tracked positions from database with proper preloading
      tracked_positions = PositionTracker.active.eager_load(:instrument).to_a
      tracked_security_ids = tracked_positions.map { |p| p.security_id.to_s }

      # Rails.logger.info("[PositionSync] Found #{tracked_positions.size} tracked positions in database")

      # Find positions that exist in DhanHQ but not in our database
      untracked_positions = find_untracked_positions(dhan_positions, tracked_security_ids)

      # Create PositionTracker records for untracked positions
      untracked_positions.each do |dhan_pos|
        create_tracker_for_position(dhan_pos)
      end

      # Check for live positions that exist in database but not in DhanHQ (should be marked as exited)
      mark_orphaned_live_positions(tracked_positions, dhan_positions)

      @last_sync = Time.current
      # Rails.logger.info("[PositionSync] Synchronization completed - created #{untracked_positions.size} trackers, marked #{orphaned_trackers.size} as exited")
    rescue StandardError
      # Rails.logger.error("[PositionSync] Failed to sync positions: #{e.class} - #{e.message}")
      # Rails.logger.error("[PositionSync] Backtrace: #{e.backtrace.first(5).join(', ')}")
    end

    def sync_paper_positions
      # Rails.logger.info('[PositionSync] Starting paper position synchronization')

      # In paper mode, we only work with PositionTracker records
      # No need to fetch from DhanHQ - paper positions don't exist there
      tracked_positions = PositionTracker.active.eager_load(:instrument).to_a
      paper_positions = tracked_positions.select(&:paper?)

      # Rails.logger.info("[PositionSync] Found #{paper_positions.size} paper positions in database")

      # Paper positions are managed entirely by our system
      # No sync needed - they're already tracked in PositionTracker
      # Just ensure they're subscribed to market feed
      paper_positions.each do |tracker|
        tracker.subscribe unless tracker.watchable.nil?
      rescue StandardError => e
        Rails.logger.warn("[PositionSync] Failed to subscribe paper position #{tracker.order_no}: #{e.message}")
      end

      @last_sync = Time.current
      # Rails.logger.info("[PositionSync] Paper position sync completed - ensured #{paper_positions.size} positions are subscribed")
    rescue StandardError => e
      Rails.logger.error("[PositionSync] Failed to sync paper positions: #{e.class} - #{e.message}")
    end

    def find_untracked_positions(dhan_positions, tracked_security_ids)
      untracked = []
      dhan_positions.each do |dhan_pos|
        security_id = extract_security_id(dhan_pos)
        next unless security_id

        unless tracked_security_ids.include?(security_id.to_s)
          untracked << dhan_pos
          # Rails.logger.warn("[PositionSync] Found untracked position: #{security_id} - #{extract_symbol(dhan_pos)}")
        end
      end
      untracked
    end

    def mark_orphaned_live_positions(tracked_positions, dhan_positions)
      # IMPORTANT: Only check live positions - paper positions don't exist in DhanHQ by design
      live_tracked_positions = tracked_positions.select(&:live?)
      orphaned_trackers = live_tracked_positions.reject do |tracker|
        dhan_positions.any? { |dp| extract_security_id(dp).to_s == tracker.security_id.to_s }
      end

      orphaned_trackers.each do |tracker|
        # Rails.logger.warn("[PositionSync] Found orphaned tracker: #{tracker.order_no} - marking as exited")
        tracker.mark_exited!
      end
    end

    def paper_trading_enabled?
      AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
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
          # Rails.logger.error("[PositionSync] Could not find derivative for #{security_id} (#{exchange_segment})")
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
          # Rails.logger.error("[PositionSync] Could not find instrument for #{security_id} (#{exchange_segment})")
          return
        end
      end

      # Generate a synthetic order number for untracked positions
      synthetic_order_no = "SYNC-#{security_id}-#{Time.current.to_i}"

      # Determine watchable: derivative for options, instrument for indices
      watchable = if segment == 'derivatives' && derivative
                    derivative
                  else
                    instrument
                  end

      # Create PositionTracker
      tracker = PositionTracker.create!(
        watchable: watchable,
        instrument: watchable.is_a?(Derivative) ? watchable.instrument : watchable, # Backward compatibility
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

      # Rails.logger.info("[PositionSync] Created tracker #{tracker.id} for untracked position #{security_id}")
    rescue StandardError
      # Rails.logger.error("[PositionSync] Failed to create tracker for position #{security_id}: #{e.class} - #{e.message}")
    end

    def calculate_paper_pnl_before_exit(tracker)
      return unless tracker.paper? && tracker.entry_price.present? && tracker.quantity.present?

      # Try to get current LTP using the same method as RiskManagerService
      ltp = get_paper_ltp(tracker)
      return unless ltp

      exit_price = BigDecimal(ltp.to_s)
      entry = BigDecimal(tracker.entry_price.to_s)
      qty = tracker.quantity.to_i
      pnl = (exit_price - entry) * qty
      pnl_pct = ((exit_price - entry) / entry * 100).round(2)

      hwm = tracker.high_water_mark_pnl || BigDecimal(0)
      hwm = [hwm, pnl].max

      tracker.update!(
        last_pnl_rupees: pnl,
        last_pnl_pct: pnl_pct,
        high_water_mark_pnl: hwm,
        avg_price: exit_price,
        meta: (tracker.meta || {}).merge(
          'exit_price' => exit_price.to_f,
          'exited_at' => Time.current,
          'exit_reason' => 'position_sync_orphaned'
        )
      )

      Rails.logger.info("[PositionSync] Paper exit PnL calculated for #{tracker.order_no}: exit_price=₹#{exit_price}, pnl=₹#{pnl}, pnl_pct=#{pnl_pct}%")
    rescue StandardError => e
      Rails.logger.error("[PositionSync] Failed to calculate PnL for paper position #{tracker.order_no}: #{e.message}")
    end

    def get_paper_ltp(tracker)
      segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
      security_id = tracker.security_id
      return nil unless segment.present? && security_id.present?

      # Try WebSocket cache first
      cached = Live::TickCache.ltp(segment, security_id)
      return BigDecimal(cached.to_s) if cached

      # Try Redis PnL cache
      tick_data = Live::RedisPnlCache.instance.fetch_tick(segment: segment, security_id: security_id)
      return BigDecimal(tick_data[:ltp].to_s) if tick_data&.dig(:ltp)

      # Try tradable's fetch method (derivative or instrument)
      tradable = tracker.tradable
      if tradable
        ltp = tradable.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
        return BigDecimal(ltp.to_s) if ltp
      end

      # Fallback: Direct API call
      begin
        response = DhanHQ::Models::MarketFeed.ltp({ segment => [security_id.to_i] })
        if response['status'] == 'success'
          option_data = response.dig('data', segment, security_id.to_s)
          return BigDecimal(option_data['last_price'].to_s) if option_data && option_data['last_price']
        end
      rescue StandardError => e
        Rails.logger.error("[PositionSync] Failed to fetch paper LTP for #{tracker.order_no}: #{e.message}")
      end
      nil
    end
  end
end
