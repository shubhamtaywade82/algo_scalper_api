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

      def performance_stats
        trades = PositionTracker.where(paper: true, status: :exited)
                                .where('meta->>\'index_key\' = ?', @symbol)
                                .where('exited_at >= ?', @start_time)

        total = trades.size
        return { count: 0 } if total.zero?

        winners = trades.count { |t| t.last_pnl_rupees.to_f > 0 }

        {
          total_trades: total,
          win_rate: (winners.to_f / total * 100).round(2),
          total_pnl: trades.sum { |t| t.last_pnl_rupees.to_f }.round(2),
          avg_pnl: (trades.sum { |t| t.last_pnl_rupees.to_f } / total).round(2),
          profit_factor: calculate_profit_factor(trades),
          max_drawdown: calculate_drawdown(trades)
        }
      end

      def exit_diagnostics
        reasons = PositionTracker
                  .where(index_key: @symbol)
                  .where(exited_at: @start_time..)
                  .group(:exit_reason)
                  .count

        {
          reason_breakdown: reasons,
          sl_hit_rate: (reasons['sl'] || 0).to_f / reasons.values.sum.to_f
        }
      end

      def signal_accuracy
        # Join TradingSignal with PositionTracker to see how signals performed
        # For simplicity, we compare TradingSignal direction vs ultimate trade outcome
        signals = TradingSignal.where(index_key: @symbol)
                               .where('created_at >= ?', @start_time)
        
        return { count: 0 } if signals.empty?

        {
          total_signals: signals.size,
          avg_confidence: signals.average(:confidence_score).to_f.round(2),
          # We check if signals resulted in a winner
          signals_with_trades: signals.count { |s| s.metadata&.dig('position_id').present? }
        }
      end

      def capture_efficiency
        analytics = TradeAnalytic
                    .joins(:position_tracker)
                    .where(position_trackers: { paper: true })
                    .where(position_trackers: { index_key: @symbol })
                    .where(position_trackers: { exited_at: @start_time.. })

        return { count: 0 } if analytics.empty?

        {
          avg_mfe: analytics.average(:max_favorable_excursion).to_f.round(2),
          avg_mae: analytics.average(:max_adverse_excursion).to_f.round(2),
          # Profit Capture = (Exit - Entry) / (Highest - Entry)
          pnl_capture_ratio: calculate_capture_ratio(analytics)
        }
      end

      def detect_leakages
        leaks = []
        stats = performance_stats
        return [] if stats[:count] == 0

        leaks << "Low win rate (#{stats[:win_rate]}%)" if stats[:win_rate] < 40
        leaks << "Negative profit factor" if stats[:profit_factor] < 1.0
        
        exits = exit_diagnostics
        leaks << "High SL hit rate (#{(exits[:sl_hit_rate]*100).round(1)}%)" if exits[:sl_hit_rate] > 0.6

        leaks
      end

      def calculate_profit_factor(trades)
        gross_profit = trades.select { |t| t.last_pnl_rupees.to_f > 0 }.sum { |t| t.last_pnl_rupees.to_f }
        gross_loss   = trades.select { |t| t.last_pnl_rupees.to_f < 0 }.sum { |t| t.last_pnl_rupees.to_f }.abs
        return gross_profit if gross_loss.zero?
        (gross_profit / gross_loss).round(2)
      end

      def calculate_drawdown(trades)
        # Simplified peak-to-trough drawdown of PnL curve
        balance = 0
        peak = 0
        max_dd = 0
        trades.order(:exited_at).each do |t|
          balance += t.last_pnl_rupees.to_f
          peak = balance if balance > peak
          dd = peak - balance
          max_dd = dd if dd > max_dd
        end
        max_dd.round(2)
      end

      def calculate_capture_ratio(analytics)
        captured = 0.0
        available = 0.0
        analytics.each do |a|
          pnl = a.exit_price - a.entry_price
          mfe = a.max_favorable_excursion
          captured += pnl if pnl > 0
          available += mfe if mfe > 0
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
