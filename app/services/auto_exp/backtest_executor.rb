# frozen_string_literal: true

require 'json'
require 'open3'

module AutoExp
  class BacktestExecutor
    SCRIPT = Rails.root.join("scripts/run_backtest.rb")

    def run
      output, status = Open3.capture2e(
        Rails.root.join('bin/rails').to_s,
        'runner',
        SCRIPT.to_s,
        chdir: Rails.root.to_s
      )

      unless status.success?
        Rails.logger.error("[AutoExp] Backtest script failed with status #{status.exitstatus}")
        raise "Backtest failed"
      end

      # Extract JSON from output (it might contain logs from Rails boot)
      json_match = output.match(/\{"profit_factor".*\}/m)

      unless json_match
        Rails.logger.error("[AutoExp] No JSON found in backtest output: #{output}")
        raise "No JSON metrics found in backtest output"
      end

      begin
        JSON.parse(json_match[0], symbolize_names: true)
      rescue JSON::ParserError => e
        Rails.logger.error("[AutoExp] Failed to parse extracted JSON: #{json_match[0]}")
        raise "Invalid JSON from backtest: #{e.message}"
      end
    end
  end
end
