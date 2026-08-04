# frozen_string_literal: true

module BacktestEngine
  class BatchRunner
    Result = Struct.new(:metrics, :results)

    def self.run(days:, strategy_class:, starting_capital:, lot_size:, risk_per_trade_pct: 1.0, **session_opts)
      new(
        days: days,
        strategy_class: strategy_class,
        starting_capital: starting_capital,
        lot_size: lot_size,
        risk_per_trade_pct: risk_per_trade_pct,
        session_opts: session_opts
      ).run
    end

    def initialize(days:, strategy_class:, starting_capital:, lot_size:, risk_per_trade_pct: 1.0, session_opts: {})
      @days = Array(days)
      @strategy_class = strategy_class
      @starting_capital = starting_capital.to_f
      @lot_size = lot_size
      @risk_per_trade_pct = risk_per_trade_pct.to_f
      @session_opts = session_opts
    end

    def run
      merged_metrics = Metrics.new
      per_day_results = []

      @days.each do |day|
        session = BacktestSession.new(
          index_candles: day[:index_candles],
          option_data: day[:option_data],
          starting_capital: @starting_capital,
          lot_size: @lot_size,
          risk_per_trade_pct: @risk_per_trade_pct
        )

        result = session.run(
          @strategy_class,
          **@session_opts
        )

        result.metrics.trades.each { |t| merged_metrics.record_trade(t) }
        result.metrics.decision_counts.each { |k, v| merged_metrics.decision_counts[k] += v }
        result.metrics.skip_reasons.each { |k, v| merged_metrics.skip_reasons[k] += v }

        per_day_results << result
      end

      Result.new(metrics: merged_metrics, results: per_day_results)
    end
  end
end
