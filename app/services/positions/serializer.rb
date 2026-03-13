# frozen_string_literal: true

module Positions
  module Serializer
    module_function

    def open(tracker)
      cache = Live::RedisPnlCache.instance.fetch_pnl(tracker.id) || {}
      ltp = (cache[:ltp] || tracker.avg_price.to_f).to_f
      entry = tracker.entry_price.to_f

      base_attributes(tracker).merge(
        entry_price: entry.round(2),
        ltp: ltp.round(2),
        pnl: (cache[:pnl] || tracker.last_pnl_rupees.to_f).round(2),
        pnl_pct: pnl_pct(entry, ltp),
        hwm_pnl: (cache[:hwm_pnl] || tracker.high_water_mark_pnl.to_f).round(2),
        entry_strategy: tracker.entry_strategy,
        time_in_position_sec: cache[:time_in_position_sec]
      )
    end

    def closed(tracker)
      entry = tracker.entry_price.to_f
      exit_p = tracker.exit_price.to_f

      base_attributes(tracker).merge(
        entry_price: entry.round(2),
        exit_price: exit_p.round(2),
        pnl: tracker.last_pnl_rupees.to_f.round(2),
        pnl_pct: pnl_pct(entry, exit_p),
        hwm_pnl: tracker.high_water_mark_pnl.to_f.round(2),
        exit_reason: tracker.exit_reason || tracker.meta&.dig('exit_reason'),
        exited_at: tracker.exited_at&.iso8601
      )
    end

    def base_attributes(tracker)
      {
        id: tracker.id,
        order_no: tracker.order_no,
        symbol: tracker.symbol,
        side: tracker.side,
        quantity: tracker.quantity.to_i,
        index_key: tracker.index_key || tracker.meta&.dig('index_key'),
        direction: tracker.direction || tracker.meta&.dig('direction'),
        segment: tracker.segment,
        paper: tracker.paper?,
        created_at: tracker.created_at.iso8601
      }
    end

    def pnl_pct(entry, current)
      return 0.0 unless entry.positive? && current.positive?

      (((current - entry) / entry) * 100).round(2)
    end
  end
end

