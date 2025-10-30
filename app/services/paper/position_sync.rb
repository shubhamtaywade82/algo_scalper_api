# frozen_string_literal: true

require 'bigdecimal'

module Paper
  # Syncs PositionTracker records (PostgreSQL) to Redis positions
  # Required on server restart to rebuild Redis state from persistent tracker records
  class PositionSync
    class << self
      def sync!
        return unless ExecutionMode.paper?

        Rails.logger.info('[Paper::PositionSync] Starting position sync from PositionTracker records...')

        active_trackers = PositionTracker.active.where("meta ->> 'paper' = 'true'")

        if active_trackers.empty?
          Rails.logger.info('[Paper::PositionSync] No active paper positions found in PositionTracker')
          return
        end

        gateway = Orders.config
        return unless gateway.is_a?(Paper::Gateway)

        synced_count = 0
        errors = []

        active_trackers.find_each do |tracker|
          sync_tracker_to_redis(gateway, tracker)
          synced_count += 1
          Rails.logger.debug { "[Paper::PositionSync] Synced tracker #{tracker.order_no} (#{tracker.security_id})" }
        rescue StandardError => e
          errors << { tracker: tracker.order_no, error: e.message }
          Rails.logger.error("[Paper::PositionSync] Failed to sync tracker #{tracker.order_no}: #{e.class} - #{e.message}")
        end

        # Recompute wallet MTM after syncing positions
        gateway.recompute_wallet_mtm

        # Adjust wallet cash to account for invested capital in positions
        # This ensures cash = seed_cash - (sum of all position investments)
        adjust_wallet_for_positions(gateway, active_trackers) if synced_count > 0

        Rails.logger.info("[Paper::PositionSync] Sync complete: #{synced_count} positions synced, #{errors.count} errors")

        Rails.logger.warn("[Paper::PositionSync] Errors: #{errors.map { |e| e[:tracker] }.join(', ')}") if errors.any?

        { synced: synced_count, errors: errors.count }
      end

      private

      def sync_tracker_to_redis(gateway, tracker)
        segment = tracker.segment || tracker.instrument&.exchange_segment || 'NSE_FNO'
        security_id = tracker.security_id.to_s

        # Check if position exists in Redis and is fresh (< 6 hours)
        if gateway.position_fresh?(segment, security_id, max_age_hours: 6)
          existing_pos = gateway.position(segment: segment, security_id: security_id)
          if existing_pos && existing_pos[:qty].to_i != 0
            Rails.logger.debug { "[Paper::PositionSync] Fresh position exists in Redis for #{segment}:#{security_id}, skipping sync" }
            return
          end
        else
          # Data exists but is stale (> 6 hours) or doesn't exist - sync from PositionTracker
          Rails.logger.info("[Paper::PositionSync] Redis data stale or missing for #{segment}:#{security_id}, syncing from PositionTracker")
        end

        # Get current LTP for calculating initial upnl
        ltp = TickCache.instance.ltp(segment, security_id.to_s)
        ltp ||= tracker.instrument&.latest_ltp&.to_f
        ltp ||= tracker.entry_price.to_f if tracker.entry_price

        entry_price = tracker.avg_price || tracker.entry_price
        return unless entry_price

        entry_price_decimal = BigDecimal(entry_price.to_s)
        qty = tracker.quantity.to_i
        return if qty.zero?

        # Calculate initial unrealized PnL
        if ltp
          upnl = (BigDecimal(ltp.to_s) - entry_price_decimal) * qty
          last_ltp = BigDecimal(ltp.to_s)
        else
          upnl = BigDecimal(0)
          last_ltp = entry_price_decimal
        end

        # Realized PnL from tracker's high water mark (if any closed positions)
        rpnl = tracker.high_water_mark_pnl ? BigDecimal(tracker.high_water_mark_pnl.to_s) : BigDecimal(0)

        # Write position to Redis
        gateway.write_position_to_redis(segment, security_id, {
                                          qty: qty,
                                          avg_price: entry_price_decimal,
                                          rpnl: rpnl,
                                          upnl: upnl,
                                          last_ltp: last_ltp
                                        })

        Rails.logger.info("[Paper::PositionSync] Restored position: #{segment}:#{security_id} qty=#{qty} @ ₹#{entry_price_decimal}")
      end

      def adjust_wallet_for_positions(gateway, trackers)
        return unless gateway.is_a?(Paper::Gateway)
        return unless gateway.instance_variable_get(:@redis)

        redis = gateway.instance_variable_get(:@redis)
        wallet_data = redis.hgetall(Paper::Gateway::WALLET_KEY)
        return if wallet_data.empty?

        # Calculate total invested capital from synced positions
        total_invested = BigDecimal(0)

        trackers.find_each do |tracker|
          segment = tracker.segment || tracker.instrument&.exchange_segment || 'NSE_FNO'
          pos = gateway.position(segment: segment, security_id: tracker.security_id)

          next unless pos && pos[:qty].to_i.positive?

          # Invested = avg_price * quantity (absolute value)
          invested = pos[:avg_price] * pos[:qty].abs
          total_invested += invested
        end

        seed_cash = BigDecimal(ENV.fetch('PAPER_SEED_CASH', '100000'))

        # Calculate available cash: seed - invested
        # This assumes positions were bought with seed cash
        new_cash = seed_cash - total_invested
        new_cash = [new_cash, BigDecimal(0)].max # Don't go negative

        # Update cash, recalculate equity with current MTM
        mtm = BigDecimal(wallet_data['mtm'] || '0')
        new_equity = new_cash + mtm

        redis.hset(Paper::Gateway::WALLET_KEY, {
                     'cash' => new_cash.to_s,
                     'equity' => new_equity.to_s
                   })

        Rails.logger.info("[Paper::PositionSync] Adjusted wallet: cash=₹#{new_cash}, invested=₹#{total_invested}, equity=₹#{new_equity}")
      end
    end
  end
end
