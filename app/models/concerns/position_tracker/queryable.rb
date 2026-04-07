# frozen_string_literal: true

class PositionTracker < ApplicationRecord
  module Queryable
    extend ActiveSupport::Concern

    included do
      scope :paper, -> { where(paper: true) }
      scope :live, -> { where(paper: false) }
      scope :exited_paper, -> { where(paper: true, status: :exited) }
      scope :today, -> { where(created_at: Time.zone.today.all_day) }
      scope :active_with_exit_requested, -> { active.where.not(exit_requested_at: nil) }
    end

    class_methods do
      def active_for(seg, sid)
        where(segment: seg, security_id: sid, status: :active).first
      end

      def exited_for(seg, sid)
        where(segment: seg, security_id: sid, status: :exited).order(id: :desc).first
      end

      def paper_trading_stats_with_pct(date: nil)
        Positions::PaperStatsQuery.call(date: date)
      end

      def paper_positions_details(limit: Positions::PaperPositionsQuery::DEFAULT_LIMIT, offset: 0)
        Positions::PaperPositionsQuery.call(limit: limit, offset: offset)
      end

      def total_paper_pnl
        exited_paper.sum do |tracker|
          tracker.last_pnl_rupees || BigDecimal(0)
        end
      end

      def active_paper_positions_count
        paper.active.count
      end

      def paper_win_rate(date: nil, exited: nil)
        return Positions::PaperStatsQuery.call(date: date)[:win_rate] if exited.nil?
        return 0.0 if exited.empty?

        winners = exited.count { |tracker| (tracker.last_pnl_rupees || 0).positive? }
        (winners.to_f / exited.size * 100).round(2)
      end

      def paper_trading_stats
        exited = exited_paper.load
        active = paper.active.load
        active_count = active.size

        # Calculate realized PnL from exited positions
        realized_pnl = total_paper_pnl.to_f

        # Calculate unrealized PnL from active positions (use Redis cache)
        unrealized_pnl = active.sum do |tracker|
          tracker.current_pnl_rupees.to_f
        end

        # Total PnL = realized (exited) + unrealized (active)
        total_pnl = realized_pnl + unrealized_pnl

        {
          total_trades: exited.size,
          active_positions: active_count,
          total_pnl: total_pnl,
          realized_pnl: realized_pnl,
          unrealized_pnl: unrealized_pnl,
          win_rate: paper_win_rate,
          average_pnl: exited.empty? ? 0.0 : (realized_pnl / exited.size).to_f,
          winners: exited.count { |t| (t.last_pnl_rupees || 0).positive? },
          losers: exited.count { |t| (t.last_pnl_rupees || 0).negative? }
        }
      end

      def clear_orphaned_redis_pnl!
        Positions::IndexSync.clear_orphaned_redis_pnl!
      end

      def should_clear_orphaned?
        @last_clear ||= 5.minutes.ago
        return true if Time.current - @last_clear >= 5.minutes

        false
      end
    end
  end
end
