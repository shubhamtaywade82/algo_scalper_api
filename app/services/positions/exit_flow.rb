# frozen_string_literal: true

module Positions
  class ExitFlow < ApplicationService
    # Used when no caller supplied a reason and meta has none (analytics / calibration).
    FALLBACK_EXIT_REASON = 'EXIT_REASON_UNSPECIFIED'

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

        metadata = tracker.meta.is_a?(Hash) ? tracker.meta.deep_stringify_keys.dup : {}
        metadata = Live::PositionRuntimeCache.instance.flush_to_meta!(metadata, tracker.id)
        resolved_reason = resolve_exit_reason_string(metadata)
        metadata['exit_reason'] = resolved_reason
        metadata['exit_triggered_at'] ||= Time.current
        metadata['hwm_pnl_pct'] = cache_data[:hwm_pnl_pct] if cache_data[:hwm_pnl_pct]

        tracker.update!(
          status: :exited,
          exit_price: exit_px,
          exited_at: resolved_exited_at,
          last_pnl_rupees: pnl_snapshot[:pnl],
          last_pnl_pct: pnl_snapshot[:pnl_pct],
          high_water_mark_pnl: pnl_snapshot[:hwm_pnl],
          exit_reason: resolved_reason,
          meta: metadata
        )

        # 5. Post-exit side effects
        Positions::DailyPnlRecorder.call(tracker: tracker)
        cleanup_exit_caches
        Positions::FeedSubscription.unsubscribe(tracker: tracker)
        register_cooldown!
        sync_final_pnl_to_database(cache_data)
        tracker.send(:broadcast_position_exited)
        post_ledger_exit!(tracker)
      end

      tracker
    end

    private

    attr_reader :tracker, :exit_price, :exited_at, :exit_reason

    def resolve_exit_reason_string(metadata)
      candidates = [
        exit_reason,
        metadata["exit_reason"],
        metadata[:exit_reason]
      ]
      picked = candidates.filter_map { |v| v.to_s.strip.presence }.first
      picked || FALLBACK_EXIT_REASON
    end

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
      return if tracker.exited?

      Live::RedisPnlCache.instance.sync_pnl_to_database(
        tracker.id,
        cache[:pnl],
        cache[:pnl_pct],
        cache[:hwm_pnl],
        cache[:hwm_pnl_pct]
      )
    end

    def post_ledger_exit!(tracker)
      Ledger::ExitPoster.post!(tracker: tracker, exit_price: tracker.exit_price)
    end

    def resolve_final_pnl(exit_price:, cache_data:)
      priced = FinalPnl.from_exit_price(
        entry_price: tracker.entry_price,
        quantity: tracker.quantity,
        exit_price: exit_price,
        is_exited: true
      )

      if priced
        hwm_pnl = [
          tracker.high_water_mark_pnl.to_f,
          cache_data[:hwm_pnl].to_f,
          priced[:pnl].to_f
        ].max

        return {
          pnl: priced[:pnl],
          pnl_pct: priced[:pnl_pct],
          hwm_pnl: hwm_pnl
        }
      end

      fallback_pnl = cache_data[:pnl] || tracker.last_pnl_rupees
      entry_bd = BigDecimal((tracker.entry_price || 0).to_s)
      qty = tracker.quantity.to_i
      capital = entry_bd * qty
      fallback_pct = if capital.positive? && fallback_pnl.present?
                       BigDecimal(fallback_pnl.to_s) / capital
                     else
                       tracker.last_pnl_pct
                     end

      {
        pnl: fallback_pnl,
        pnl_pct: fallback_pct,
        hwm_pnl: [tracker.high_water_mark_pnl.to_f, cache_data[:hwm_pnl].to_f].max
      }
    end
  end
end
