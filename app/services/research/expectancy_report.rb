# frozen_string_literal: true

module Research
  # The actual "Context -> Expectancy Map" deliverable: groups persisted
  # Research::PremiumLifecycle rows by a chosen subset of their entry-time
  # Research::ContextClassifier regime labels, and computes per-bucket
  # sample size / avg return / win rate / avg time-to-peak / avg drawdown —
  # answering "what underlying context produced high-expectancy premium
  # expansion" instead of "buy when RSI is 60".
  #
  # Grouping by all ~10 regime dimensions at once would fragment a modest
  # dataset into mostly-empty buckets, so callers choose a small subset
  # (defaulting to the three that most directly describe "is this a
  # tradeable trend day"). Buckets are computed in Ruby rather than SQL —
  # this is a research/reporting tool over a small persisted table, not a
  # hot path, and jsonb-path grouping in SQL would be far less readable for
  # no real benefit at this data volume.
  class ExpectancyReport
    ALL_DIMENSIONS = %w[
      market_structure trend volatility_regime momentum volume_regime
      time_context vwap_relation liquidity_sweep opening_range_breakout gap
    ].freeze
    DEFAULT_DIMENSIONS = %w[trend opening_range_breakout volatility_regime].freeze
    PHASES = %w[entry peak].freeze

    class << self
      # @param scope [ActiveRecord::Relation<Research::PremiumLifecycle>]
      # @param dimensions [Array<String>] subset of ALL_DIMENSIONS to group by
      # @param phase ["entry", "peak"] which underlying_context snapshot to read regime labels from
      # @return [Array<Hash>] buckets ranked by avg_return_pct descending
      def call(scope:, dimensions: DEFAULT_DIMENSIONS, phase: "entry")
        validate!(dimensions, phase)

        rows = scope.filter_map { |lifecycle| row_for(lifecycle, dimensions, phase) }
        rows
          .group_by { |row| row[:context] }
          .map { |context, group| summarize(context, group) }
          .sort_by { |bucket| -(bucket[:avg_return_pct] || -Float::INFINITY) }
      end

      private

      def validate!(dimensions, phase)
        unknown = Array(dimensions) - ALL_DIMENSIONS
        raise ArgumentError, "unknown dimensions: #{unknown.join(', ')}" if unknown.any?
        raise ArgumentError, "dimensions must not be empty" if Array(dimensions).empty?
        raise ArgumentError, "phase must be one of #{PHASES.join(', ')}" unless PHASES.include?(phase)
      end

      def row_for(lifecycle, dimensions, phase)
        regime = lifecycle.underlying_context&.dig(phase, "regime") || {}
        context = dimensions.index_with { |dim| regime[dim] || "unknown" }

        {
          context: context,
          return_pct: lifecycle.peak_return_pct&.to_f,
          end_return_pct: lifecycle.end_return_pct&.to_f,
          minutes_to_peak: lifecycle.minutes_to_peak,
          drawdown_pct: lifecycle.max_drawdown_after_peak_pct&.to_f
        }
      end

      def summarize(context, group)
        returns = group.filter_map { |row| row[:return_pct] }
        end_returns = group.filter_map { |row| row[:end_return_pct] }
        drawdowns = group.filter_map { |row| row[:drawdown_pct] }
        times = group.filter_map { |row| row[:minutes_to_peak] }
        wins = returns.count(&:positive?)

        {
          context: context,
          sample_size: group.size,
          avg_return_pct: average(returns),
          avg_end_return_pct: average(end_returns),
          # win_rate_pct is peak-based (return_pct = peak_return_pct, the max favorable
          # excursion) and is virtually always >= 0 over a multi-hour window — it reads
          # ~100% for almost any bucket and isn't a meaningful "would this have made
          # money" signal. end_win_rate_pct is the realized-return-based counterpart.
          win_rate_pct: returns.empty? ? nil : ((wins.to_f / returns.size) * 100).round(2),
          end_win_rate_pct: end_returns.empty? ? nil : ((end_returns.count(&:positive?).to_f / end_returns.size) * 100).round(2),
          avg_time_to_peak_minutes: average(times),
          avg_drawdown_pct: average(drawdowns)
        }
      end

      def average(values)
        return nil if values.empty?

        (values.sum.to_f / values.size).round(4)
      end
    end
  end
end
