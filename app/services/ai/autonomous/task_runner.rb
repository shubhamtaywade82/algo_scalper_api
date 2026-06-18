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
          instrument = IndexInstrumentCache.instance.get_or_fetch(key: symbol)
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
            Rails.logger.info("[TaskRunner] [DRY_RUN] Would apply trailing params to algo.yml for #{symbol}: #{params.inspect}")
            return
          end

          # Reusing logic from optimize_trailing.rake but in a service context
          config_path = Rails.root.join('config/algo.yml')
          config = YAML.safe_load(File.read(config_path))
          
          idx_key = symbol.downcase
          if config['risk'] && config['risk']['institutional_trailing']
            config['risk']['institutional_trailing'][idx_key] ||= {}
            params.each do |k, v|
              config['risk']['institutional_trailing'][idx_key][k.to_s] = v
            end
            File.write(config_path, config.to_yaml)
            Rails.logger.info("[TaskRunner] Applied trailing params to algo.yml for #{symbol}")
          end
        end
      end
    end
  end
end
