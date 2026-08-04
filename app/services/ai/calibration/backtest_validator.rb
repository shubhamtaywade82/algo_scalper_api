# frozen_string_literal: true

module Ai
  module Calibration
    # Validates AI-suggested parameter changes against paper trade history.
    #
    # Simulates how the suggested parameters would have affected past trades
    # using Backtest::Metrics. Rejects changes that make performance worse by
    # more than REGRESSION_TOLERANCE.
    #
    # Usage:
    #   result = Ai::Calibration::BacktestValidator.call(trades:, proposed_patch:)
    #   result[:approved]          # true/false
    #   result[:baseline_metrics]  # win_rate, profit_factor, max_drawdown
    #   result[:projected_metrics] # same keys with proposed params
    #   result[:rejection_reason]  # string if rejected
    class BacktestValidator
      # Allow up to 10% degradation in projected total PnL vs baseline
      REGRESSION_TOLERANCE = 0.10

      class ValidationFailed < StandardError; end

      def self.call(trades:, proposed_patch:)
        new(trades: trades, proposed_patch: proposed_patch).call
      end

      def initialize(trades:, proposed_patch:)
        @trades         = Array(trades)
        @proposed_patch = proposed_patch
      end

      def call
        return reject!("No trades to validate against") if @trades.empty?
        return reject!("No parameter changes proposed") if @proposed_patch.blank?

        baseline_trades  = simulate_trades(baseline_config)
        projected_trades = simulate_trades(merged_config)

        baseline_metrics  = compute_metrics(baseline_trades)
        projected_metrics = compute_metrics(projected_trades)

        baseline_pnl  = baseline_trades.sum { |t| t[:pnl] }
        projected_pnl = projected_trades.sum { |t| t[:pnl] }

        # Reject if projected PnL is worse by more than tolerance
        threshold = baseline_pnl * (1 - REGRESSION_TOLERANCE)
        if projected_pnl < threshold
          return reject!(
            "Projected PnL ₹#{projected_pnl.round(2)} is #{REGRESSION_TOLERANCE * 100}%+ " \
            "worse than baseline ₹#{baseline_pnl.round(2)}",
            baseline_metrics: baseline_metrics,
            projected_metrics: projected_metrics
          )
        end

        {
          approved:          true,
          baseline_metrics:  baseline_metrics,
          projected_metrics: projected_metrics,
          baseline_pnl:      baseline_pnl.round(2),
          projected_pnl:     projected_pnl.round(2),
          pnl_delta:         (projected_pnl - baseline_pnl).round(2),
          rejection_reason:  nil
        }
      end

      private

      def baseline_config
        @baseline_config ||= begin
          cfg = AlgoConfig.fetch
          {
            sl_pct:  cfg.dig(:risk, :sl_pct).to_f,
            tp_pct:  cfg.dig(:risk, :tp_pct).to_f
          }
        rescue StandardError
          { sl_pct: 0.10, tp_pct: 0.25 }
        end
      end

      def merged_config
        sl = @proposed_patch.dig('risk', 'sl_pct') || baseline_config[:sl_pct]
        tp = @proposed_patch.dig('risk', 'tp_pct') || baseline_config[:tp_pct]
        {
          sl_pct: sl.to_f,
          tp_pct: tp.to_f
        }
      end

      # Simulates how trades would have performed with the given SL/TP config.
      # We re-apply exits based on the new thresholds against each trade's
      # historical PnL percentage (simplified, not a full tick replay).
      def simulate_trades(config)
        @trades.map do |trade|
          entry   = trade[:entry_price].to_f
          exit_p  = trade[:exit_price].to_f
          qty     = 1 # normalised — direction/quantity already captured in pnl

          next trade if entry.zero?

          # Standard clamping based on simulated SL/TP
          # Note: Without full tick data, we assume the trade hit the tighter of
          # baseline vs new config if it was a winner, or the new SL if it was a loser.
          # For now, we use simple clamping as a heuristic.
          raw_pnl_pct = (exit_p - entry) / entry.to_f
          effective_pnl_pct = apply_sl_tp(raw_pnl_pct, config[:sl_pct], config[:tp_pct])

          { pnl: entry * effective_pnl_pct * qty }
        end.compact
      end

      def apply_sl_tp(pnl_pct, sl_pct, tp_pct)
        # Clamp between -SL and +TP
        [[-sl_pct, pnl_pct].max, tp_pct].min
      end

      def compute_metrics(trades)
        metrics = Backtest::Metrics.new(trades: trades)
        {
          win_rate:       (metrics.win_rate * 100).round(2),
          profit_factor:  metrics.profit_factor.round(2),
          max_drawdown:   metrics.max_drawdown.round(2)
        }
      end

      def reject!(reason, extra = {})
        Rails.logger.warn("[BacktestValidator] Rejected: #{reason}")
        {
          approved:         false,
          rejection_reason: reason,
          **extra
        }
      end
    end
  end
end
