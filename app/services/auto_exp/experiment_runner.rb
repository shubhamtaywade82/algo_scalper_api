# frozen_string_literal: true

require "yaml"
require "shellwords"
require_relative "llm_planner"
require_relative "config_applier"
require_relative "backtest_executor"
require_relative "evaluator"
require_relative "results_store"

module AutoExp
  class ExperimentRunner
    def initialize
      @planner = AutoExp::LlmPlanner.new
      @applier = AutoExp::ConfigApplier.new
      @executor = AutoExp::BacktestExecutor.new
      @evaluator = AutoExp::Evaluator.new
      @best_metrics = nil
    end

    def run(iterations: 10)
      Rails.logger.debug "Starting AutoExp Runner..."

      iterations.times do |i|
        Rails.logger.debug "\n--- Iteration #{i + 1}/#{iterations} ---"

        begin
          # 1. Load context
          config = YAML.load_file(AutoExp::ConfigApplier::CONFIG_PATH)
          results = AutoExp::ResultsStore.load_recent

          # 2. Propose mutation
          Rails.logger.debug "Asking LLM for next hypothesis..."
          decision = @planner.propose(results: results, config: config)

          unless decision && decision["parameter"]
            Rails.logger.debug "LLM failed to propose a valid decision."
            next
          end

          Rails.logger.debug "Mutation Proposed:"
          Rails.logger.debug " - Parameter: #{decision['parameter']}"
          Rails.logger.debug " - New Value: #{decision['value']}"
          Rails.logger.debug " - Reason:    #{decision['reason']}"

          # 3. Apply mutation
          @applier.apply(
            parameter: decision["parameter"],
            value: decision["value"]
          )

          # 4. Execute backtest
          Rails.logger.debug "Running backtest..."
          metrics = @executor.run

          Rails.logger.debug "Backtest Metrics:"
          Rails.logger.debug " - Profit Factor: #{metrics[:profit_factor]}"
          Rails.logger.debug " - Drawdown:      #{metrics[:drawdown]}"
          Rails.logger.debug " - Win Rate:      #{metrics[:win_rate]}"

          # 5. Evaluate
          if @evaluator.improved?(metrics, @best_metrics)
            Rails.logger.debug "SUCCESS: Metrics improved! Keeping change."
            status = "keep"
            @best_metrics = metrics
            commit(decision["reason"])
          else
            Rails.logger.debug "REJECT: Metrics did not improve. Reverting."
            status = "discard"
            revert
          end

          # 6. Log results
          AutoExp::ResultsStore.log(
            commit: current_commit,
            metrics: metrics,
            status: status,
            description: decision["reason"]
          )
        rescue StandardError => e
          Rails.logger.debug "Error during iteration #{i + 1}: #{e.message}"
          # puts e.backtrace.first(10).join("\n")
          # Attempt to revert just in case
          begin
            revert
          rescue StandardError
            nil
          end
        end
      end

      Rails.logger.debug "\nAutoExp completed."
      Rails.logger.debug "Best metrics achieved: #{@best_metrics.inspect}" if @best_metrics
    end

    private

    def commit(reason)
      escaped_reason = Shellwords.escape("autoexp: #{reason}")
      system("git add #{AutoExp::ConfigApplier::CONFIG_PATH}")
      system("git commit -m #{escaped_reason} --no-verify")
    end

    def revert
      # Revert ONLY the config file to its state in HEAD
      system("git checkout HEAD -- #{AutoExp::ConfigApplier::CONFIG_PATH}")
    end

    def current_commit
      `git rev-parse --short HEAD`.strip
    end
  end
end
