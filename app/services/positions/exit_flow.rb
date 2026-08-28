# frozen_string_literal: true

module Positions
  class ExitFlow < ApplicationService
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
        pnl_stats = resolved_final_pnl(cache_data)
        final_hwm = [tracker.high_water_mark_pnl.to_f, cache_data[:hwm_pnl].to_f, pnl_stats[:pnl].to_f].max

        metadata = build_metadata(cache_data)
        decision_data = build_decision

        tracker.update!(
          status: :exited,
          exit_price: resolved_exit_price,
          exited_at: resolved_exited_at,
          exit_triggered_at: metadata['exit_triggered_at'],
          last_pnl_rupees: pnl_stats[:pnl],
          last_pnl_pct: pnl_stats[:pnl_pct],
          high_water_mark_pnl: final_hwm,
          exit_reason: metadata['exit_reason'],
          meta: metadata,
          decision: decision_data
        )

        execute_post_exit_effects(pnl_stats[:pnl], cache_data)
      end

      tracker
    end

    private

    attr_reader :tracker, :exit_price, :exited_at, :exit_reason

    def resolved_final_pnl(cache_data)
      if resolved_exit_price && tracker.entry_price&.positive? && tracker.quantity&.nonzero?
        Positions::FinalPnl.from_exit_price(
          entry_price: tracker.entry_price,
          quantity: tracker.quantity,
          exit_price: resolved_exit_price,
          is_exited: true,
          position_side: tracker.side
        ) || fallback_pnl(cache_data)
      else
        fallback_pnl(cache_data)
      end
    end

    def fallback_pnl(cache_data)
      {
        pnl: cache_data[:pnl] || tracker.last_pnl_rupees,
        pnl_pct: cache_data[:pnl_pct] || tracker.last_pnl_pct
      }
    end

    def build_metadata(cache_data)
      meta = tracker.meta.is_a?(Hash) ? tracker.meta.dup : {}
      actual_reason = exit_reason.to_s.strip.presence || meta['exit_reason'].to_s.strip.presence || FALLBACK_EXIT_REASON
      meta['exit_reason'] = actual_reason
      meta['exit_triggered_at'] ||= Time.current
      meta['hwm_pnl_pct'] = cache_data[:hwm_pnl_pct] if cache_data[:hwm_pnl_pct]
      meta
    end

    def build_decision
      decision = tracker.decision.is_a?(Hash) ? tracker.decision.dup : {}
      analytics = begin
        Positions::ExitAnalyticsBuilder.build(tracker: tracker, exit_price: resolved_exit_price)
      rescue StandardError
        {}
      end
      analytics.is_a?(Hash) ? decision.merge(analytics.stringify_keys) : decision
    end

    def execute_post_exit_effects(final_pnl_rupees, cache_data)
      Portfolio::PnlTracker.mark_realized(tracker_id: tracker.id, pnl: final_pnl_rupees.to_f)
      Ledger::ExitPoster.post!(tracker: tracker)
      Positions::DailyPnlRecorder.call(tracker: tracker)
      tracker.send(:cleanup_exit_caches)
      Positions::FeedSubscription.unsubscribe(tracker: tracker)
      tracker.send(:register_cooldown!)
      sync_final_pnl_to_database(cache_data)
      tracker.send(:broadcast_position_exited)
    end

    def resolved_exit_price
      price = exit_price || tracker.send(:fetch_ltp_from_cache)
      price.present? ? BigDecimal(price.to_s) : nil
    end

    def resolved_exited_at
      exited_at || Time.current
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
