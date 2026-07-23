# frozen_string_literal: true

module Research
  # Ranks Research::ExitCaptureAnalyzer's exit strategies per regime bucket,
  # instead of one aggregate number across every trade — shaped like
  # Research::ExpectancyReport (group by regime dimension) but reusing
  # Research::ResearchReportGenerator.evaluate_exits for the stats math
  # instead of reimplementing win-rate/expectancy/Sharpe a third time.
  #
  # Scoped to strike_label "ATM" only: evaluate_exits looks up every trade's
  # exits under one caller-given strike_label key, so mixing strike labels
  # inside a single call would silently zero out rows whose real strike
  # doesn't match instead of excluding them cleanly.
  class RegimeExitReport
    REGIME_STRATEGY_NAME = "regime_scan"
    ATM_STRIKE_LABEL = "ATM"
    DEFAULT_DIMENSIONS = %w[trend volatility_regime liquidity_sweep].freeze

    class << self
      def call(scope:, dimensions: DEFAULT_DIMENSIONS)
        rows = scope.where(strike_label: ATM_STRIKE_LABEL)
                    .includes(:research_signal)
                    .filter_map { |candidate| row_for(candidate, dimensions) }

        rows
          .group_by { |row| row[:context] }
          .map { |context, group| summarize(context, group) }
          .sort_by { |bucket| -(bucket[:best_strategy_return_pct] || -Float::INFINITY) }
      end

      private

      def row_for(candidate, dimensions)
        return nil unless candidate.research_signal.strategy_name == REGIME_STRATEGY_NAME
        return nil if candidate.exit_simulations.blank?

        regime = candidate.research_signal.metadata["regime"] || {}
        context = dimensions.index_with { |dim| regime[dim] || "unknown" }

        { context: context, strike_label: candidate.strike_label, exit_simulations: candidate.exit_simulations }
      end

      def summarize(context, group)
        trades = group.map do |row|
          { strikes: { row[:strike_label] => { exits: row[:exit_simulations].deep_symbolize_keys } } }
        end

        strategies = Research::ResearchReportGenerator.evaluate_exits(trades, strike_label: group.first[:strike_label])
        ranked = strategies.sort_by { |_name, stats| -(stats[:avg_return_pct] || -Float::INFINITY) }.to_h
        best = ranked.first

        {
          context: context,
          sample_size: group.size,
          strategies: ranked,
          best_strategy: best&.first,
          best_strategy_return_pct: best&.last&.dig(:avg_return_pct)
        }
      end
    end
  end
end
