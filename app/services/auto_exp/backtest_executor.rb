# frozen_string_literal: true

require 'English'
require "json"

module AutoExp
  class BacktestExecutor
    SCRIPT = Rails.root.join("scripts/run_backtest.rb")

    def run
      # Run the script using rails runner to ensure environment is loaded
      # Capture stdout for the JSON metrics and ignore stderr (or handle separately)
      output = `rails runner #{SCRIPT}`

      unless $CHILD_STATUS.success?
        Rails.logger.error("[AutoExp] Backtest script failed with status #{$CHILD_STATUS.exitstatus}")
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
