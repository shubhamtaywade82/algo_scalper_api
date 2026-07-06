# frozen_string_literal: true

module Ai
  module Autonomous
    # Unifies the execution of various optimization tools (solvers).
    # Handles Rake task invocation or direct service calls.
    class TaskRunner
      def self.run(solver_key, symbol, days = 30, dry_run: false)
        case solver_key.to_s
        when 'indicator_tuning'
          run_indicator_optimization(symbol, days, dry_run: dry_run)
        when 'trailing_optimization'
          run_trailing_optimization(symbol, dry_run: dry_run)
        else
          raise "Unknown solver: #{solver_key}"
        end
      end

      class << self
        private

        def run_indicator_optimization(symbol, days, dry_run: false)
          index_cfg = IndiaIndexRegistry.for_key(symbol) || { key: symbol }
          instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
          return { error: 'Instrument not found' } unless instrument

          # Run for the primary indicators
          results = {}
          %i[adx supertrend].each do |indicator|
            optimizer = Optimization::SingleIndicatorOptimizer.new(
              instrument: instrument,
              interval: '5', # Default to 5m for index
              indicator: indicator,
              lookback_days: days,
              dry_run: dry_run
            )
            results[indicator] = optimizer.run
          end
          results
        end

        def run_trailing_optimization(symbol, dry_run: false)
          optimizer = Optimization::TrailingOptimizer.new(index_key: symbol)
          result = optimizer.optimize

          if result && result[:best_params]
            # We need to apply these to algo.yml as TrailingOptimizer doesn't self-persist yet
            apply_trailing_params(symbol, result[:best_params], dry_run: dry_run)
          end
          result
        end

        def apply_trailing_params(symbol, params, dry_run: false)
          if dry_run
            Rails.logger.info("[TaskRunner] [DRY_RUN] Would apply trailing params to algo_config_document for #{symbol}: #{params.inspect}")
            return
          end

          idx_key = symbol.to_s.downcase
          patch = {
            risk: {
              institutional_trailing: {
                idx_key.to_sym => params.transform_keys(&:to_sym)
              }
            }
          }

          AlgoConfig::DocumentStore.apply_deep_merge_patch!(
            patch,
            source: 'ai_autonomous_trailing',
            actor: 'TaskRunner',
            metadata: { index_key: idx_key }
          )
          Rails.logger.info("[TaskRunner] Applied trailing params to algo_config_document for #{symbol}")
        end
      end
    end
  end
end
