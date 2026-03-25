# frozen_string_literal: true

module Positions
  class PaperPositionsQuery < ApplicationService
    DEFAULT_LIMIT = 200
    DEFAULT_OFFSET = 0

    def initialize(limit: DEFAULT_LIMIT, offset: DEFAULT_OFFSET)
      @limit = limit.to_i
      @offset = offset.to_i
    end

    def call
      scoped_positions.map { |tracker| serialize(tracker) }
    end

    private

    attr_reader :limit, :offset

    def scoped_positions
      PositionTracker.paper
                     .includes(:instrument)
                     .order(created_at: :desc)
                     .limit(limit.positive? ? limit : DEFAULT_LIMIT)
                     .offset(offset.positive? ? offset : DEFAULT_OFFSET)
    end

    def serialize(tracker)
      entry_price = tracker.entry_price.to_f
      exit_price = tracker.status == 'exited' ? tracker.exit_price.to_f : nil
      current_price = exit_price || tracker.avg_price.to_f

      {
        id: tracker.id,
        order_no: tracker.order_no,
        symbol: tracker.symbol,
        side: tracker.side,
        status: tracker.status,
        quantity: tracker.quantity.to_i,
        entry_price: entry_price,
        exit_price: exit_price,
        avg_price: tracker.avg_price.to_f,
        last_pnl_rupees: tracker.last_pnl_rupees.to_f.round(2),
        last_pnl_pct: pnl_pct_for(tracker, entry_price, current_price).round(2),
        high_water_mark_pnl: tracker.high_water_mark_pnl.to_f,
        created_at: tracker.created_at&.strftime('%Y-%m-%d %H:%M'),
        updated_at: tracker.updated_at&.strftime('%Y-%m-%d %H:%M'),
        watchable_type: tracker.watchable_type,
        segment: tracker.segment,
        security_id: tracker.security_id,
        paper: tracker.paper?,
        unrealized: tracker.status != 'exited'
      }
    end

    def pnl_pct_for(tracker, entry_price, current_price)
      return tracker.last_pnl_pct.to_f * 100.0 if tracker.last_pnl_pct.present?
      return 0.0 unless entry_price.positive? && current_price.positive?

      if tracker.side == 'BUY'
        (current_price - entry_price) / entry_price * 100.0
      else
        (entry_price - current_price) / entry_price * 100.0
      end
    end
  end
end
