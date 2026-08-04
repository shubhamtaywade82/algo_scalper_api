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

        cache_data = Live::RedisPnlCache.instance.fetch_pnl(tracker.id) || {}
        exit_px = resolved_exit_price
        pnl_snapshot = resolve_final_pnl(exit_price: exit_px, cache_data: cache_data)

        metadata = Live::PositionRuntimeCache.instance.flush_to_meta!({}, tracker.id) || {}
        resolved_reason = metadata["exit_reason"].presence || metadata["exit_triggered_at"].presence || FALLBACK_EXIT_REASON
        exit_triggered_at = metadata["exit_triggered_at"].presence || Time.current
        decision = Positions::ExitAnalyticsBuilder.build(tracker: tracker, exit_price: exit_px).stringify_keys
        decision["exit_reason"] = resolved_reason
        decision["exit_triggered_at"] = exit_triggered_at
        if cache_data[:hwm_pnl_pct]
          decision["hwm_pnl_pct"] = cache_data[:hwm_pnl_pct]
        end

        tracker.update!(
          status: :exited,
          exit_price: exit_px,
          exited_at: resolved_exited_at,
          last_pnl_rupees: pnl_snapshot[:pnl],
          last_pnl_pct: pnl_snapshot[:pnl_pct],
          high_water_mark_pnl: pnl_snapshot[:hwm_pnl],
          exit_reason: resolved_reason,
          exit_triggered_at: exit_triggered_at,
          hwm_pnl_pct: cache_data[:hwm_pnl_pct],
          decision: decision,
          meta: metadata
        )

        # 5. Post-exit side effects
        Positions::DailyPnlRecorder.call(tracker: tracker)
        cleanup_exit_caches
        tracker.unsubscribe
        register_cooldown!
        sync_final_pnl_to_database(cache_data)
        tracker.send(:broadcast_position_exited)
        post_ledger_exit!(tracker)
      end

      tracker
    end

    private

    attr_reader :tracker, :exit_price, :exited_at, :exit_reason

    def persist_final_pnl_from_cache
      tracker.send(:persist_final_pnl_from_cache)
    end

    def update_exit_attributes
      tracker.send(:update_exit_attributes, resolved_exit_price, resolved_exited_at, exit_metadata)
    end

    def resolved_exit_price
      return @resolved_exit_price if defined?(@resolved_exit_price)

      price = exit_price || tracker.send(:fetch_ltp_from_cache)
      @resolved_exit_price = price.present? ? BigDecimal(price.to_s) : nil
    end

    def resolved_exited_at
      exited_at || Time.current
    end

    def exit_metadata
      tracker.send(:prepare_exit_metadata, exit_reason)
    end

    def cleanup_exit_caches
      tracker.send(:cleanup_exit_caches)
    end

    def register_cooldown!
      tracker.send(:register_cooldown!)
    end

    def sync_final_pnl_to_database
      cache = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
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
