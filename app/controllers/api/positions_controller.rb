# frozen_string_literal: true

module Api
  class PositionsController < ApplicationController
    def index
      render json: {
        open: open_positions,
        closed: closed_positions
      }
    end

    private

    def open_positions
      PositionTracker.active.includes(:watchable, :instrument).map { |tracker| serialize_open(tracker) }
    end

    def closed_positions
      today = Time.zone.today
      PositionTracker.exited
                     .where(exited_at: today.all_day)
                     .includes(:watchable, :instrument)
                     .order(exited_at: :desc)
                     .map { |tracker| serialize_closed(tracker) }
    end

    def serialize_open(tracker)
      cache = Live::RedisPnlCache.instance.fetch_pnl(tracker.id) || {}
      ltp    = (cache[:ltp] || tracker.avg_price.to_f).to_f
      entry  = tracker.entry_price.to_f
      {
        id: tracker.id,
        order_no: tracker.order_no,
        symbol: tracker.symbol,
        side: tracker.side,
        quantity: tracker.quantity.to_i,
        entry_price: entry.round(2),
        ltp: ltp.round(2),
        pnl: (cache[:pnl] || tracker.last_pnl_rupees.to_f).round(2),
        pnl_pct: pnl_pct(entry, ltp),
        hwm_pnl: (cache[:hwm_pnl] || tracker.high_water_mark_pnl.to_f).round(2),
        index_key: tracker.index_key || tracker.meta&.dig('index_key'),
        direction: tracker.direction || tracker.meta&.dig('direction'),
        entry_strategy: tracker.entry_strategy,
        segment: tracker.segment,
        paper: tracker.paper?,
        time_in_position_sec: cache[:time_in_position_sec],
        created_at: tracker.created_at.iso8601
      }
    end

    def serialize_closed(tracker)
      entry = tracker.entry_price.to_f
      exit_p = tracker.exit_price.to_f
      {
        id: tracker.id,
        order_no: tracker.order_no,
        symbol: tracker.symbol,
        side: tracker.side,
        quantity: tracker.quantity.to_i,
        entry_price: entry.round(2),
        exit_price: exit_p.round(2),
        pnl: tracker.last_pnl_rupees.to_f.round(2),
        pnl_pct: pnl_pct(entry, exit_p),
        hwm_pnl: tracker.high_water_mark_pnl.to_f.round(2),
        exit_reason: tracker.exit_reason || tracker.meta&.dig('exit_reason'),
        index_key: tracker.index_key || tracker.meta&.dig('index_key'),
        direction: tracker.direction || tracker.meta&.dig('direction'),
        segment: tracker.segment,
        paper: tracker.paper?,
        exited_at: tracker.exited_at&.iso8601,
        created_at: tracker.created_at.iso8601
      }
    end

    def pnl_pct(entry, current)
      return 0.0 unless entry.positive? && current.positive?

      (((current - entry) / entry) * 100).round(2)
    end
  end
end
