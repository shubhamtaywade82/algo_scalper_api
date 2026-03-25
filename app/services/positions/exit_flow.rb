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
      tracker.state_machine.transition_to!(:exited)
      persist_final_pnl_from_cache
      update_exit_attributes
      Positions::DailyPnlRecorder.call(tracker: tracker)
      cleanup_exit_caches
      Positions::FeedSubscription.unsubscribe(tracker: tracker)
      register_cooldown!
      sync_final_pnl_to_database
      tracker.send(:broadcast_position_exited)
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
