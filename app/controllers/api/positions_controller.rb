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
      PositionTracker.active.includes(:watchable, :instrument).map { |t| serialize_open(t) }
    end

    def closed_positions
      today = Time.zone.today
      PositionTracker.exited
                     .where(exited_at: today.beginning_of_day..today.end_of_day)
                     .includes(:watchable, :instrument)
                     .order(exited_at: :desc)
                     .map { |t| serialize_closed(t) }
    end

    def serialize_open(t)
      cache = Live::RedisPnlCache.instance.fetch_pnl(t.id) || {}
      {
        id: t.id,
        order_no: t.order_no,
        symbol: t.symbol,
        side: t.side,
        quantity: t.quantity.to_i,
        entry_price: t.entry_price.to_f,
        ltp: (cache[:ltp] || t.avg_price.to_f).round(2),
        pnl: (cache[:pnl] || t.last_pnl_rupees.to_f).round(2),
        pnl_pct: ((cache[:pnl_pct] || t.last_pnl_pct.to_f) * 100).round(2),
        hwm_pnl: (cache[:hwm_pnl] || t.high_water_mark_pnl.to_f).round(2),
        index_key: t.index_key || t.meta&.dig('index_key'),
        direction: t.direction || t.meta&.dig('direction'),
        entry_strategy: t.entry_strategy,
        segment: t.segment,
        paper: t.paper?,
        time_in_position_sec: cache[:time_in_position_sec],
        created_at: t.created_at.iso8601
      }
    end

    def serialize_closed(t)
      {
        id: t.id,
        order_no: t.order_no,
        symbol: t.symbol,
        side: t.side,
        quantity: t.quantity.to_i,
        entry_price: t.entry_price.to_f,
        exit_price: t.exit_price.to_f,
        pnl: t.last_pnl_rupees.to_f.round(2),
        pnl_pct: (t.last_pnl_pct.to_f * 100).round(2),
        hwm_pnl: t.high_water_mark_pnl.to_f.round(2),
        exit_reason: t.exit_reason || t.meta&.dig('exit_reason'),
        index_key: t.index_key || t.meta&.dig('index_key'),
        direction: t.direction || t.meta&.dig('direction'),
        segment: t.segment,
        paper: t.paper?,
        exited_at: t.exited_at&.iso8601,
        created_at: t.created_at.iso8601
      }
    end
  end
end
