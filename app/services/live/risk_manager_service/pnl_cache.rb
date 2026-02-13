# frozen_string_literal: true

module Live
  class RiskManagerService
    module PnlCache
      private

      # Check if enforcement should be skipped (market closed and no positions)
      def skip_enforcement_due_to_market_closed?
        TradingSession::Service.market_closed? && Positions::ActivePositionsCache.instance.active_trackers.empty?
      end

      # Fetch live broker positions keyed by security_id (string). Returns {} on paper mode or failure.
      def fetch_positions_indexed
        return {} if paper_trading_enabled?

        positions = DhanHQ::Models::Position.active.each_with_object({}) do |position, map|
          security_id = position.respond_to?(:security_id) ? position.security_id : position[:security_id]
          map[security_id.to_s] = position if security_id
        end
        begin
          Live::FeedHealthService.instance.mark_success!(:positions)
        rescue StandardError
          nil
        end
        positions
      rescue StandardError => e
        Rails.logger.error("[RiskManager] fetch_positions_indexed failed: #{e.class} - #{e.message}")
        begin
          Live::FeedHealthService.instance.mark_failure!(:positions, error: e)
        rescue StandardError
          nil
        end
        {}
      end

      def paper_trading_enabled?
        AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
      rescue StandardError
        false
      end

      # Returns a cached pnl snapshot for tracker (expects Redis cache to be maintained elsewhere)
      def pnl_snapshot(tracker)
        Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] pnl_snapshot error for #{tracker.id}: #{e.class} - #{e.message}")
        nil
      end

      def update_paper_positions_pnl_if_due(last_update_time)
        # if last_update_time is nil or stale, update now
        return unless Time.current - (last_update_time || Time.zone.at(0)) >= 1.minute

        update_paper_positions_pnl
      rescue StandardError => e
        Rails.logger.error("[RiskManager] update_paper_positions_pnl_if_due failed: #{e.class} - #{e.message}")
      end

      # Update PnL for all paper trackers and cache in Redis (same semantics as before)
      def update_paper_positions_pnl
        paper_trackers = PositionTracker.paper.active.includes(:instrument).to_a
        return if paper_trackers.empty?

        paper_trackers.each do |tracker|
          next unless tracker.entry_price.present? && tracker.quantity.present?

          ltp = get_paper_ltp(tracker)
          unless ltp
            Rails.logger.debug { "[RiskManager] No LTP for paper tracker #{tracker.order_no}" }
            next
          end

          entry = BigDecimal(tracker.entry_price.to_s)
          exit_price = BigDecimal(ltp.to_s)
          qty = tracker.quantity.to_i
          gross_pnl = (exit_price - entry) * qty

          # Deduct broker fees (₹20 per order, ₹40 per trade if exited)
          pnl = BrokerFeeCalculator.net_pnl(gross_pnl, is_exited: tracker.exited?)
          pnl_pct = entry.positive? ? ((exit_price - entry) / entry) : nil

          hwm = tracker.high_water_mark_pnl || BigDecimal(0)
          hwm = [hwm, pnl].max

          tracker.update!(
            last_pnl_rupees: pnl,
            last_pnl_pct: pnl_pct ? BigDecimal(pnl_pct.to_s) : nil,
            high_water_mark_pnl: hwm
          )

          update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
        rescue StandardError => e
          Rails.logger.error("[RiskManager] update_paper_positions_pnl failed for #{tracker.order_no}: #{e.class} - #{e.message}")
        end

        Rails.logger.info('[RiskManager] Paper PnL update completed')
      end

      # Ensure every active PositionTracker has an entry in Redis PnL cache (best-effort)
      # Throttled to avoid excessive queries - only runs every 5 seconds
      def ensure_all_positions_in_redis
        # Skip if market closed and no active positions (avoid unnecessary DB queries)
        if TradingSession::Service.market_closed?
          active_count = Positions::ActivePositionsCache.instance.active_trackers.size
          return if active_count.zero?
        end

        @last_ensure_all ||= Time.zone.at(0)
        return if Time.current - @last_ensure_all < 5.seconds

        trackers = PositionTracker.active.includes(:instrument).to_a
        return if trackers.empty?

        @last_ensure_all = Time.current

        positions = fetch_positions_indexed

        trackers.each do |tracker|
          redis_pnl = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
          next if redis_pnl && (Time.current.to_i - (redis_pnl[:timestamp] || 0)) < 10

          position = positions[tracker.security_id.to_s]
          tracker.hydrate_pnl_from_cache!

          ltp = if tracker.paper?
                  get_paper_ltp(tracker)
                else
                  current_ltp(tracker, position)
                end

          next unless ltp

          pnl = compute_pnl(tracker, position, ltp)
          next unless pnl

          pnl_pct = compute_pnl_pct(tracker, ltp, position)
          update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
        rescue StandardError => e
          Rails.logger.error("[RiskManager] ensure_all_positions_in_redis failed for #{tracker.order_no}: #{e.class} - #{e.message}")
        end
      end

      # Compute current LTP (will try cache, API, tradable, etc.)
      def current_ltp(tracker, position = nil)
        return get_paper_ltp(tracker) if tracker.paper?

        if position.respond_to?(:exchange_segment) && position.exchange_segment == 'NSE_FNO'
          begin
            response = DhanHQ::Models::MarketFeed.ltp({ 'NSE_FNO' => [tracker.security_id.to_i] })
            if response['status'] == 'success'
              option_data = response.dig('data', 'NSE_FNO', tracker.security_id.to_s)
              if option_data && option_data['last_price']
                ltp = BigDecimal(option_data['last_price'].to_s)
                begin
                  Live::RedisPnlCache.instance.store_tick(segment: 'NSE_FNO', security_id: tracker.security_id, ltp: ltp,
                                                          timestamp: Time.current)
                rescue StandardError
                  nil
                end
                return ltp
              end
            end
          rescue StandardError => e
            Rails.logger.error("[RiskManager] current_ltp(fetch option) failed for #{tracker.order_no}: #{e.class} - #{e.message}")
          end
        end

        tradable = tracker.tradable
        return tradable.ltp if tradable&.ltp

        segment = tracker.segment.presence || tracker.instrument&.exchange_segment
        cached = Live::TickCache.ltp(segment, tracker.security_id)
        return BigDecimal(cached.to_s) if cached

        fetch_ltp(position, tracker)
      end

      def get_paper_ltp(tracker)
        segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
        security_id = tracker.security_id
        return nil unless segment.present? && security_id.present?

        cached = Live::TickCache.ltp(segment, security_id)
        return BigDecimal(cached.to_s) if cached

        tick_data = begin
          Live::TickCache.fetch(segment, security_id)
        rescue StandardError
          nil
        end
        return BigDecimal(tick_data[:ltp].to_s) if tick_data&.dig(:ltp)

        tradable = tracker.tradable
        if tradable
          ltp = begin
            tradable.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
          rescue StandardError
            nil
          end
          return BigDecimal(ltp.to_s) if ltp
        end

        begin
          response = DhanHQ::Models::MarketFeed.ltp({ segment => [security_id.to_i] })
          if response['status'] == 'success'
            option_data = response.dig('data', segment, security_id.to_s)
            return BigDecimal(option_data['last_price'].to_s) if option_data && option_data['last_price']
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] get_paper_ltp API error for #{tracker.order_no}: #{e.class} - #{e.message}")
        end

        nil
      end

      def fetch_ltp(position, tracker)
        segment = if position.respond_to?(:exchange_segment) then position.exchange_segment
                  elsif position.is_a?(Hash) then position[:exchange_segment]
                  end
        segment ||= tracker.instrument&.exchange_segment
        cached = begin
          Live::TickCache.ltp(segment, tracker.security_id)
        rescue StandardError
          nil
        end
        return BigDecimal(cached.to_s) if cached

        nil
      end

      def compute_pnl(tracker, position, ltp)
        if position.respond_to?(:net_qty) && position.respond_to?(:cost_price)
          quantity = position.net_qty.to_i
          cost_price = position.cost_price.to_f
          return nil if quantity.zero? || cost_price.zero?

          (ltp - BigDecimal(cost_price.to_s)) * quantity
        else
          quantity = tracker.quantity.to_i
          if quantity.zero? && position
            quantity = position.respond_to?(:quantity) ? position.quantity.to_i : (position[:quantity] || 0).to_i
          end
          return nil if quantity.zero?

          entry_price = tracker.entry_price || tracker.avg_price
          return nil if entry_price.blank?

          (ltp - BigDecimal(entry_price.to_s)) * quantity
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] compute_pnl failed for #{tracker.id}: #{e.class} - #{e.message}")
        nil
      end

      def compute_pnl_pct(tracker, ltp, position = nil)
        if position.respond_to?(:cost_price)
          cost_price = position.cost_price.to_f
          return nil if cost_price.zero?

          (ltp - BigDecimal(cost_price.to_s)) / BigDecimal(cost_price.to_s)
        else
          entry_price = tracker.entry_price || tracker.avg_price
          return nil if entry_price.blank?

          (ltp - BigDecimal(entry_price.to_s)) / BigDecimal(entry_price.to_s)
        end
      rescue StandardError
        nil
      end

      def update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
        return unless pnl && ltp&.to_f&.positive?

        Live::PnlUpdaterService.instance.cache_intermediate_pnl(
          tracker_id: tracker.id,
          pnl: pnl,
          pnl_pct: pnl_pct,
          ltp: ltp,
          hwm: tracker.high_water_mark_pnl
        )
      rescue StandardError => e
        Rails.logger.error("[RiskManager] update_pnl_in_redis failed for #{tracker.order_no}: #{e.class} - #{e.message}")
      end
    end
  end
end
