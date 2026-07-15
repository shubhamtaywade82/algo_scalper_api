# frozen_string_literal: true

# Bootstrap Rails Environment
require_relative "../../config/environment"

# Set up parameters from environment variables or use sensible defaults
SYMBOL        = ENV.fetch("SYMBOL", "NIFTY")
LOOKBACK_DAYS = ENV.fetch("LOOKBACK_DAYS", "365").to_i
TARGET_POINTS = ENV.fetch("TARGET_POINTS", "50").to_f
OUTPUT_DIR    = ENV.fetch("OUTPUT_DIR", "data/research")
DB_ONLY       = ENV.fetch("DB_ONLY", "false") == "true"

Rails.logger.debug "\n#{'=' * 80}"
Rails.logger.debug "🚀 RUNNING NIFTY FIRST-15m BREAKOUT & OPTION PREMIUM RESEARCH"
Rails.logger.debug "=" * 80
Rails.logger.debug "Symbol:        #{SYMBOL}"
Rails.logger.debug "Lookback Days: #{LOOKBACK_DAYS}"
Rails.logger.debug "Target Points: #{TARGET_POINTS} points"
Rails.logger.debug "Database Only: #{DB_ONLY}"
Rails.logger.debug "Output Dir:    #{OUTPUT_DIR}"
Rails.logger.debug "Rails Env:     #{Rails.env}"
Rails.logger.debug "=" * 80

begin
  report = Research::First15mEngine.run(
    symbol: SYMBOL,
    lookback_days: LOOKBACK_DAYS,
    target_points: TARGET_POINTS,
    output_dir: OUTPUT_DIR,
    db_only: DB_ONLY
  )

  if report.any?
    Rails.logger.debug "\n✅ Research run completed successfully! Output reports saved to: #{OUTPUT_DIR}/"
  else
    Rails.logger.debug "\n❌ Research run returned no results. Check if NIFTY candles are in the database."
  end
rescue StandardError => e
  Rails.logger.debug "\n💥 Research execution failed: #{e.class} - #{e.message}"
  Rails.logger.debug e.backtrace.first(10).join("\n")
  exit 1
end
