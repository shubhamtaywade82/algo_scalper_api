# frozen_string_literal: true

module BacktestEngine
  class Optimizer
    RunResult = Struct.new(:params, :metrics, :analytics, keyword_init: true)

    DEFAULT_OBJECTIVE = :expectancy

    def self.run(days:, strategy_class:, param_grid:, starting_capital:, lot_size:, objective: DEFAULT_OBJECTIVE, **batch_opts)
      new(
        days: days,
        strategy_class: strategy_class,
        param_grid: param_grid,
        starting_capital: starting_capital,
        lot_size: lot_size,
        objective: objective,
        batch_opts: batch_opts
      ).run
    end

    def initialize(days:, strategy_class:, param_grid:, starting_capital:, lot_size:, objective: DEFAULT_OBJECTIVE, batch_opts: {})
      @days = Array(days)
      @strategy_class = strategy_class
      @param_grid = param_grid
      @starting_capital = starting_capital.to_f
      @lot_size = lot_size
      @objective = objective.to_sym
      @batch_opts = batch_opts
    end

    def run
      results = @param_grid.map { |params| run_one(params) }
      rank(results)
    end

    private

    def run_one(params)
      batch_result = BatchRunner.run(
        days: apply_params_to_days(@days, params),
        strategy_class: @strategy_class,
        starting_capital: @starting_capital,
        lot_size: @lot_size,
        **@batch_opts
      )

      merged_equity = batch_result.results.flat_map { |r| r.portfolio.equity_curve }
      analytics = Analytics::TradeAnalytics.from_metrics(
        batch_result.metrics,
        equity_curve: merged_equity.any? ? merged_equity : nil
      )

      RunResult.new(
        params: params,
        metrics: batch_result.metrics,
        analytics: analytics
      )
    end

    def apply_params_to_days(days, params)
      return days if params.nil? || params.empty?

      days.map do |day|
        day.merge(day_type: params[:day_type] || day[:day_type])
      end
    end

    def rank(results)
      results.sort_by { |r| -objective_value(r) }
    end

    def objective_value(run_result)
      a = run_result.analytics
      case @objective
      when :expectancy then a.expectancy
      when :profit_factor then a.profit_factor == Float::INFINITY ? 1e6 : a.profit_factor
      when :total_pnl then a.total_pnl
      when :win_rate then a.win_rate
      else a.expectancy
      end
    end
  end
end
