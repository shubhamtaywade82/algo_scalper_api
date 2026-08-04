# frozen_string_literal: true

module BacktestEngine
  module Analytics
    class TradeAnalytics
      attr_reader :total_pnl, :total_trades, :win_rate, :avg_win, :avg_loss,
                  :expectancy, :profit_factor, :max_drawdown,
                  :by_session, :by_regime, :by_day_type,
                  :avg_mfe, :avg_mae, :avg_exit_efficiency, :avg_trend_capture_pct,
                  :by_exit_reason

      def self.from_metrics(metrics, equity_curve: nil)
        new(
          trades: metrics.trades,
          equity_curve: equity_curve
        )
      end

      def self.from_result(result)
        new(
          trades: result.metrics.trades,
          equity_curve: result.portfolio.equity_curve
        )
      end

      def self.from_results(results)
        trades = results.flat_map { |r| r.metrics.trades }
        equity_curve = build_merged_equity_curve(results)
        new(trades: trades, equity_curve: equity_curve)
      end

      def initialize(trades:, equity_curve: nil)
        @trades = Array(trades)
        @equity_curve = equity_curve
        @total_pnl = compute_total_pnl
        @total_trades = @trades.size
        @win_rate = compute_win_rate
        @avg_win = compute_avg_win
        @avg_loss = compute_avg_loss
        @expectancy = compute_expectancy
        @profit_factor = compute_profit_factor
        @max_drawdown = compute_max_drawdown
        @by_session = breakdown(:session)
        @by_regime = breakdown(:regime)
        @by_day_type = breakdown(:day_type)
        @avg_mfe = compute_avg_metric(:mfe)
        @avg_mae = compute_avg_metric(:mae)
        @avg_exit_efficiency = compute_avg_metric(:exit_efficiency)
        @avg_trend_capture_pct = compute_avg_metric(:trend_capture_pct)
        @by_exit_reason = breakdown(:exit_reason)
      end

      def to_h
        {
          total_pnl: total_pnl,
          total_trades: total_trades,
          win_rate: win_rate,
          avg_win: avg_win,
          avg_loss: avg_loss,
          expectancy: expectancy,
          profit_factor: profit_factor,
          max_drawdown: max_drawdown,
          by_session: by_session,
          by_regime: by_regime,
          by_day_type: by_day_type,
          avg_mfe: avg_mfe,
          avg_mae: avg_mae,
          avg_exit_efficiency: avg_exit_efficiency,
          avg_trend_capture_pct: avg_trend_capture_pct,
          by_exit_reason: by_exit_reason
        }
      end

      def summary
        [
          "Total PnL: #{total_pnl.round(2)}",
          "Trades: #{total_trades}",
          "Win rate: #{win_rate.round(1)}%",
          "Expectancy: #{expectancy.round(2)}",
          "Profit factor: #{profit_factor.round(2)}",
          "Max drawdown: #{(max_drawdown * 100).round(1)}%",
          "Avg Exit Efficiency: #{avg_exit_efficiency.round(1)}%"
        ].join(" | ")
      end

      private

      def self.build_merged_equity_curve(results)
        return nil if results.empty?
        return results.first.portfolio.equity_curve if results.size == 1

        results.flat_map { |r| r.portfolio.equity_curve }
      end

      def compute_total_pnl
        @trades.sum { |t| pnl_value(t) }
      end

      def pnl_value(trade)
        return trade.to_f if trade.is_a?(Numeric)
        return trade[:pnl].to_f if trade.respond_to?(:[]) && trade[:pnl]
        return trade.pnl.to_f if trade.respond_to?(:pnl)

        0.0
      end

      def compute_win_rate
        return 0.0 if @trades.empty?

        wins = @trades.count { |t| pnl_value(t).positive? }
        (wins.to_f / @trades.size) * 100.0
      end

      def compute_avg_win
        wins = @trades.select { |t| pnl_value(t).positive? }
        return 0.0 if wins.empty?

        wins.sum { |t| pnl_value(t) } / wins.size
      end

      def compute_avg_loss
        losses = @trades.select { |t| pnl_value(t).negative? }
        return 0.0 if losses.empty?

        losses.sum { |t| pnl_value(t) } / losses.size
      end

      def compute_expectancy
        return 0.0 if @trades.empty?

        total_pnl / @trades.size
      end

      def compute_profit_factor
        gross_profit = @trades.sum { |t| [pnl_value(t), 0].max }
        gross_loss = @trades.sum { |t| [pnl_value(t), 0].min }.abs
        return 0.0 if gross_loss.zero? && gross_profit.zero?
        return Float::INFINITY if gross_loss.zero?

        gross_profit / gross_loss
      end

      def compute_max_drawdown
        if @equity_curve.is_a?(Array) && @equity_curve.any?
          peak = @equity_curve.first
          max_dd = 0.0
          @equity_curve.each do |value|
            peak = [peak, value].max
            dd = peak.positive? ? (peak - value) / peak : 0.0
            max_dd = [max_dd, dd].max
          end
          return max_dd
        end

        running = 0.0
        peak = 0.0
        max_dd = 0.0
        @trades.each do |t|
          running += pnl_value(t)
          peak = [peak, running].max
          dd = peak.positive? ? (peak - running) / peak : 0.0
          max_dd = [max_dd, dd].max
        end
        max_dd
      end

      def breakdown(key)
        return {} if @trades.empty?

        valid_key = key.to_sym
        return {} unless Metrics::Trade.members.include?(valid_key)

        grouped = @trades.group_by do |t|
          t.respond_to?(valid_key) ? t.public_send(valid_key) : t[valid_key]
        end

        grouped.transform_values do |group_trades|
          {
            pnl: group_trades.sum { |t| pnl_value(t) },
            count: group_trades.size
          }
        end
      end

      def compute_avg_metric(key)
        return 0.0 if @trades.empty?
        valid_trades = @trades.select { |t| t.respond_to?(key) && t.public_send(key) }
        return 0.0 if valid_trades.empty?

        valid_trades.sum { |t| t.public_send(key).to_f } / valid_trades.size
      end
    end
  end
end
