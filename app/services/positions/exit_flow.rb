# frozen_string_literal: true

module Positions
  class ExitFlow < ApplicationService
    def initialize(tracker:, exit_price: nil, exited_at: nil, exit_reason: nil)
      @tracker = tracker
      @exit_price = exit_price
      @exited_at = exited_at
      @exit_reason = exit_reason
    end

    def call
      tracker.reload
      tracker.with_lock do
        tracker.reload
        return tracker if tracker.exited?

        tracker.state_machine.transition_to!(:exited)

        # 1. Fetch final stats from cache (if any)
        cache_data = Live::RedisPnlCache.instance.fetch_pnl(tracker.id) || {}

        # 2. Build exit attributes without triggering persistence yet
        final_pnl_rupees = cache_data[:pnl] || tracker.last_pnl_rupees
        final_hwm_pnl = [tracker.high_water_mark_pnl.to_f, cache_data[:hwm_pnl].to_f, final_pnl_rupees.to_f].max

        # 3. Build metadata
        metadata = tracker.meta.is_a?(Hash) ? tracker.meta.dup : {}
        metadata["exit_reason"] = exit_reason || metadata["exit_reason"]
        metadata["exit_triggered_at"] ||= Time.current
        metadata["hwm_pnl_pct"] = cache_data[:hwm_pnl_pct] if cache_data[:hwm_pnl_pct]

        # 4. Final update! (This is atomic)
        tracker.update!(
          status: :exited,
          exit_price: resolved_exit_price,
          exited_at: resolved_exited_at,
          last_pnl_rupees: final_pnl_rupees,
          high_water_mark_pnl: final_hwm_pnl,
          exit_reason: metadata["exit_reason"],
          meta: metadata
        )

        # 5. Post-exit side effects
        Positions::DailyPnlRecorder.call(tracker: tracker)
        cleanup_exit_caches
        Positions::FeedSubscription.unsubscribe(tracker: tracker)
        register_cooldown!
        sync_final_pnl_to_database(cache_data)
        tracker.send(:broadcast_position_exited)
      end

      tracker
    end

    private

    attr_reader :tracker, :exit_price, :exited_at, :exit_reason

    def resolved_exit_price
      price = exit_price || tracker.send(:fetch_ltp_from_cache)
      price.present? ? BigDecimal(price.to_s) : nil
    end

    def resolved_exited_at
      exited_at || Time.current
    end

    def cleanup_exit_caches
      tracker.send(:cleanup_exit_caches)
    end

    def register_cooldown!
      tracker.send(:register_cooldown!)
    end

    def sync_final_pnl_to_database(cache)
      return unless cache && cache[:pnl]

      Live::RedisPnlCache.instance.sync_pnl_to_database(
        tracker.id,
        cache[:pnl],
        cache[:pnl_pct],
        cache[:hwm_pnl],
        cache[:hwm_pnl_pct]
      )
    end
  end
end
