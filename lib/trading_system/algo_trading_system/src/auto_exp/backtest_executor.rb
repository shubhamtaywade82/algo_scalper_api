# frozen_string_literal: true

require 'json'
require_relative '../utils/logger'

module AutoExp
  class BacktestExecutor
    SCRIPT = File.join(Dir.pwd, 'scripts', 'run_backtest.rb')

    def run
      # Ensure script exists
      unless File.exist?(SCRIPT)
        # Create a dummy script if it doesn't exist (to be filled later)
        ::Utils::Logger.warn('auto_exp.backtest_script_missing', path: SCRIPT)
      end

      # We run the script and expect JSON output on stdout
      output = `bundle exec ruby #{SCRIPT}`

      unless $?.success?
        ::Utils::Logger.error('auto_exp.backtest_failed', output: output)
        raise 'Backtest execution failed'
      end

      begin
        JSON.parse(output, symbolize_names: true)
      rescue JSON::ParserError => e
        ::Utils::Logger.error('auto_exp.json_failed', error: e.message, output: output)
        raise "Invalid JSON from backtest: #{e.message}"
      end
    end
  end
end
