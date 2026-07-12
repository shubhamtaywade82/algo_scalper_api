# frozen_string_literal: true

require 'yaml'
require_relative 'llm_planner'
require_relative 'config_applier'
require_relative 'backtest_executor'
require_relative 'evaluator'
require_relative 'results_store'
require_relative '../utils/logger'

module AutoExp
  class ExperimentRunner
    CONFIG_FILE = 'config/strategy_config.yml'

    def run(max_iterations: 100)
      planner = LlmPlanner.new
      applier = ConfigApplier.new
      executor = BacktestExecutor.new
      evaluator = Evaluator.new

      best_metrics = nil
      iteration = 0

      loop do
        iteration += 1
        break if iteration > max_iterations

        ::Utils::Logger.info('auto_exp.iteration_start', iteration: iteration)

        # Load current config and past results
        config = YAML.load_file(CONFIG_FILE) rescue {}
        results = load_results

        # 1. Propose mutation via LLM
        decision = planner.propose(results: results, config: config)
        unless decision
          ::Utils::Logger.warn('auto_exp.no_decision', iteration: iteration)
          next
        end

        ::Utils::Logger.info('auto_exp.propose', parameter: decision['parameter'], value: decision['value'], reason: decision['reason'])

        # 2. Apply mutation to config
        applier.apply(
          parameter: decision['parameter'],
          value: decision['value']
        )

        # 3. Commit the change
        commit(decision['reason'])

        # 4. Run Backtest
        begin
          metrics = executor.run
          ::Utils::Logger.info('auto_exp.backtest_result', metrics: metrics)
        rescue StandardError => e
          ::Utils::Logger.error('auto_exp.backtest_error', error: e.message)
          revert
          next
        end

        # 5. Evaluate results
        if evaluator.improved?(metrics, best_metrics)
          status = 'keep'
          best_metrics = metrics
          ::Utils::Logger.info('auto_exp.status_keep', metrics: metrics)
        else
          status = 'discard'
          ::Utils::Logger.info('auto_exp.status_discard', metrics: metrics)
          revert
        end

        # 6. Log results
        ResultsStore.log(
          commit: current_commit,
          metrics: metrics,
          status: status,
          description: decision['reason']
        )
      end
    end

    private

    def commit(reason)
      # Ensure git user name and email are set for this repo
      system("git config --local user.name 'AutoExp Bot'")
      system("git config --local user.email 'autoexp@trading.local'")
      
      system("git add #{CONFIG_FILE}")
      system("git commit -m 'autoexp: #{reason}' --no-verify")
    end

    def revert
      system('git reset --hard HEAD~1')
    end

    def current_commit
      `git rev-parse --short HEAD`.strip
    end

    def load_results
      # Load last 100 results from TSV if it exists
      return [] unless File.exist?(ResultsStore::FILE)
      
      results = []
      CSV.foreach(ResultsStore::FILE, col_sep: "\t", headers: true) do |row|
        results << {
          commit: row['commit'],
          profit_factor: row['profit_factor'].to_f,
          drawdown: row['drawdown'].to_f,
          status: row['status']
        }
      end
      results.last(100)
    end
  end
end
