# frozen_string_literal: true

module Ai
  module Autonomous
    # Generates a diagnostic performance report by cross-referencing:
    # - PositionTracker PnL (exited positions)
    # - TradeAnalytic (MFE/MAE efficiency)
    # - TradingSignal (accuracy and diagnostic metadata)
    class Auditor
      def self.report(symbol:, days: 30)
        new(symbol: symbol, days: days).report
      end

      def initialize(symbol:, days:)
        @symbol = symbol.upcase
        @days   = days
        @start_time = days.days.ago.beginning_of_day
      end

      def report
        {
          symbol: @symbol,
          period: "#{@days} days",
          timestamp: Time.current,
          performance: performance_stats,
          exits: exit_diagnostics,
          signals: signal_accuracy,
          efficiency: capture_efficiency,
          problems: detect_leakages
        }
      end

      private

      # Memoized so detect_leakages reuses the same result without a second query set.
      def performance_stats
        @performance_stats ||= begin
          scope = exited_scope
          total = scope.count

          if total.zero?
            { total_trades: 0 }
          else
            # Use DB-level aggregates — no need to load all records into memory
            total_pnl = scope.sum(:last_pnl_rupees).to_f
            winners   = scope.where('last_pnl_rupees > 0').count

            {
              total_trades: total,
              win_rate: (winners.to_f / total * 100).round(2),
              total_pnl: total_pnl.round(2),
              avg_pnl: (total_pnl / total).round(2),
              profit_factor: calculate_profit_factor(scope),
              max_drawdown: calculate_drawdown(scope)
            }
          end
        end
      end

      def exit_diagnostics
        reasons = PositionTracker
                  .where(index_key: @symbol)
                  .where(exited_at: @start_time..)
                  .group(:exit_reason)
                  .count

        total = reasons.values.sum.to_f
        {
          reason_breakdown: reasons,
          sl_hit_rate: total.zero? ? 0.0 : (reasons['sl'] || 0).to_f / total
        }
      end

      def signal_accuracy
        scope = TradingSignal
                .where(index_key: @symbol)
                .where(created_at: @start_time..)

        total = scope.count
        return { count: 0 } if total.zero?

        {
          total_signals: total,
          avg_confidence: scope.average(:confidence_score).to_f.round(2),
          # Count only signals that have a linked position_id in metadata
          signals_with_trades: scope.where("metadata->>'position_id' IS NOT NULL").count
        }
      end

      def capture_efficiency
        analytics = TradeAnalytic
                    .joins(:position_tracker)
                    .where(position_trackers: { paper: true })
                    .where(position_trackers: { index_key: @symbol })
                    .where(position_trackers: { exited_at: @start_time.. })

        count = analytics.count
        return { count: 0 } if count.zero?

        {
          count: count,
          avg_mfe: analytics.average(:max_favorable_excursion).to_f.round(2),
          avg_mae: analytics.average(:max_adverse_excursion).to_f.round(2),
          pnl_capture_ratio: calculate_capture_ratio(analytics)
        }
      end

      def detect_leakages
        stats = performance_stats # memoized — no extra query
        return [] if stats[:total_trades].to_i.zero?

        leaks = []
        leaks << "Low win rate (#{stats[:win_rate]}%)" if stats[:win_rate] < 40
        leaks << 'Negative profit factor' if stats[:profit_factor] < 1.0

        exits = exit_diagnostics
        if exits[:sl_hit_rate] > 0.6
          leaks << "High SL hit rate (#{(exits[:sl_hit_rate] * 100).round(1)}%)"
        end

        leaks
      end

      # Uses DB WHERE conditions to avoid loading all records for gross profit/loss.
      def calculate_profit_factor(scope)
        gross_profit = scope.where('last_pnl_rupees > 0').sum(:last_pnl_rupees).to_f
        gross_loss   = scope.where('last_pnl_rupees < 0').sum(:last_pnl_rupees).to_f.abs
        return gross_profit if gross_loss.zero?

        (gross_profit / gross_loss).round(2)
      end

      # Drawdown requires sequential iteration — must load records ordered by exit time.
      def calculate_drawdown(scope)
        balance = 0.0
        peak    = 0.0
        max_dd  = 0.0

        scope.order(:exited_at).find_each(batch_size: 1000) do |tracker|
          pnl = tracker.last_pnl_rupees.to_f
          balance += pnl
          peak     = balance if balance > peak
          dd       = peak - balance
          max_dd   = dd if dd > max_dd
        end

        max_dd.round(2)
      end

      # Capture ratio still needs per-row data — no DB aggregate available for this formula.
      def calculate_capture_ratio(analytics)
        captured  = 0.0
        available = 0.0

        analytics.find_each(batch_size: 1000) do |analytic|
          pnl = analytic.exit_price.to_f - analytic.entry_price.to_f
          captured  += pnl if pnl.positive?
          available += analytic.max_favorable_excursion.to_f if analytic.max_favorable_excursion.to_f.positive?
        end

        return 0.0 if available.zero?

        (captured / available).round(2)
      end

      def exited_scope
        PositionTracker
          .where(paper: true, status: :exited)
          .where(index_key: @symbol)
          .where(exited_at: @start_time..)
      end
    end
  end
end
