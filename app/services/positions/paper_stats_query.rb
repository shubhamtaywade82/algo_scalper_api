# frozen_string_literal: true

module Positions
  class PaperStatsQuery < ApplicationService
    def initialize(date: nil, paper: :auto)
      @date = date
      @paper = paper
    end

    def call
      stats = build_stats
      return stats if stats[:total_trades].positive? || paper != :auto

      fallback = self.class.new(date: date, paper: :all).send(:build_stats)
      return stats unless fallback[:total_trades].positive?

      fallback.merge(stats_scope: 'all')
    end

    private

    attr_reader :date, :paper

    def build_stats
      reset_memoized_scopes!
      total = total_pnl_rupees
      peak_mode = resolved_paper_filter.nil? ? AlgoConfig.paper_trading_enabled? : resolved_paper_filter
      Portfolio::PaperPeakTracker.observe!(total, paper: peak_mode)
      stored_peak = Portfolio::PaperPeakTracker.current_for(paper: peak_mode)
      peak = [stored_peak, total].max

      {
        total_trades: exited_scope.count,
        active_positions: active_positions.size,
        total_pnl_rupees: total.round(2),
        total_pnl_pct: pnl_pct(total).round(2),
        realized_pnl_rupees: realized_pnl_rupees.round(2),
        realized_pnl_pct: pnl_pct(realized_pnl_rupees).round(2),
        unrealized_pnl_rupees: unrealized_pnl_rupees.round(2),
        unrealized_pnl_pct: pnl_pct(unrealized_pnl_rupees).round(2),
        win_rate: win_rate.round(2),
        avg_realized_pnl_pct: avg_realized_pnl_pct.round(2),
        avg_unrealized_pnl_pct: avg_unrealized_pnl_pct.round(2),
        winners: winners_count,
        losers: losers_count,
        is_blocked: Portfolio::DrawdownGuard.triggered?,
        blocked_reason: Portfolio::DrawdownGuard.triggered? ? 'Drawdown Guard Active' : nil,
        peak_pnl: peak.round(2),
        paper_mode: resolved_paper_filter.nil? ? nil : resolved_paper_filter,
        stats_scope: stats_scope_label
      }
    end

    def stats_scope_label
      return 'all' if resolved_paper_filter.nil?

      resolved_paper_filter ? 'paper' : 'live'
    end

    def reset_memoized_scopes!
      @exited_scope = nil
      @active_positions = nil
      @realized_pnl_rupees = nil
      @unrealized_pnl_rupees = nil
      @winners_count = nil
      @losers_count = nil
    end

    def resolved_paper_filter
      return nil if paper == :all
      return paper if paper.in?([true, false])

      AlgoConfig.paper_trading_enabled?
    end

    def exited_scope
      @exited_scope ||= begin
        scope = PositionTracker.where(status: :exited).where(exited_at: date_range)
        filter = resolved_paper_filter
        filter.nil? ? scope : scope.where(paper: filter)
      end
    end

    def active_positions
      @active_positions ||= begin
        scope = PositionTracker.where(status: :active)
        filter = resolved_paper_filter
        filter.nil? ? scope.to_a : scope.where(paper: filter).to_a
      end
    end

    def realized_pnl_rupees
      @realized_pnl_rupees ||= exited_scope.sum(:last_pnl_rupees).to_f
    end

    def unrealized_pnl_rupees
      @unrealized_pnl_rupees ||= active_positions.sum { |t| t.current_pnl_rupees.to_f }
    end

    def total_pnl_rupees
      realized_pnl_rupees + unrealized_pnl_rupees
    end

    def winners_count
      @winners_count ||= exited_scope.where('last_pnl_rupees > 0').count
    end

    def losers_count
      @losers_count ||= exited_scope.where('last_pnl_rupees < 0').count
    end

    def win_rate
      total = exited_scope.count
      return 0.0 if total.zero?

      (winners_count.to_f / total) * 100.0
    end

    def avg_realized_pnl_pct
      values = exited_scope.where.not(last_pnl_pct: nil).pluck(:last_pnl_pct)
      return 0.0 if values.empty?

      (values.sum(&:to_f) * 100.0) / values.size.to_f
    end

    def avg_unrealized_pnl_pct
      return 0.0 if active_positions.empty?

      values = active_positions.map { |t| (t.current_pnl_pct || 0).to_f * 100.0 }
      values.sum / values.size.to_f
    end

    def pnl_pct(pnl_rupees)
      initial_capital = Capital::Allocator.paper_trading_balance.to_f
      return 0.0 unless initial_capital.positive?

      pnl_rupees / initial_capital * 100.0
    end

    def date_range
      target_date = date || Time.zone.today
      target_date.all_day
    end
  end
end
