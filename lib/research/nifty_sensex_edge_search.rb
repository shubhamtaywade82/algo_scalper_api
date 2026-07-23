# frozen_string_literal: true

require_relative "../../config/environment"

LOOKBACK_NIFTY  = ENV.fetch("LOOKBACK_DAYS_NIFTY", "250").to_i   # NIFTY: ~250 days already cached, effectively free
LOOKBACK_SENSEX = ENV.fetch("LOOKBACK_DAYS_SENSEX", "150").to_i  # SENSEX: costs live API calls
TARGET_POINTS   = ENV.fetch("TARGET_POINTS", "50").to_f
OUTPUT_ROOT     = ENV.fetch("OUTPUT_ROOT", "data/research/v6_nifty_sensex")

Rails.logger.debug "\n#{'=' * 80}"
Rails.logger.debug "🔍 NIFTY/SENSEX NAKED OPTIONS EDGE SEARCH"
Rails.logger.debug "=" * 80
Rails.logger.debug "NIFTY lookback:  #{LOOKBACK_NIFTY} days (db_only)"
Rails.logger.debug "SENSEX lookback: #{LOOKBACK_SENSEX} days (live fetch)"
Rails.logger.debug "Target points:   #{TARGET_POINTS}"
Rails.logger.debug "Output root:     #{OUTPUT_ROOT}"
Rails.logger.debug "=" * 80

Rails.logger.debug "\n[1/3] Backfilling SENSEX underlying candles..."
sensex_days = Research::UnderlyingBackfill.call(symbol: "SENSEX", lookback_days: LOOKBACK_SENSEX)
Rails.logger.debug "  SENSEX underlying days now cached: #{sensex_days}"

Rails.logger.debug "\n[2/3] Running First15mEngine per symbol..."
nifty_report = Research::First15mEngine.run(
  symbol: "NIFTY", lookback_days: LOOKBACK_NIFTY, target_points: TARGET_POINTS,
  output_dir: "#{OUTPUT_ROOT}/nifty", db_only: true
)
Rails.logger.debug "  NIFTY trades: #{nifty_report[:trades]&.size || 0}"

sensex_report = Research::First15mEngine.run(
  symbol: "SENSEX", lookback_days: LOOKBACK_SENSEX, target_points: TARGET_POINTS,
  output_dir: "#{OUTPUT_ROOT}/sensex", db_only: false
)
Rails.logger.debug "  SENSEX trades: #{sensex_report[:trades]&.size || 0}"

combined_trades = (nifty_report[:trades] || []) + (sensex_report[:trades] || [])
Rails.logger.debug "\n[3/3] Finalizing combined NIFTY+SENSEX hypothesis test (n=#{combined_trades.size})..."

if combined_trades.empty?
  Rails.logger.debug "\n❌ No trades from either symbol. Nothing to finalize."
  exit 1
end

combined_report = Research::First15mEngine.finalize(combined_trades, output_dir: "#{OUTPUT_ROOT}/combined")

if combined_report.any?
  Rails.logger.debug "\n✅ Edge search complete. Reports at:"
  Rails.logger.debug "   #{OUTPUT_ROOT}/nifty/research_report_v4.json"
  Rails.logger.debug "   #{OUTPUT_ROOT}/sensex/research_report_v4.json"
  Rails.logger.debug "   #{OUTPUT_ROOT}/combined/research_report_v4.json  <- headline hypothesis test"
else
  Rails.logger.debug "\n❌ Combined finalize returned no results."
  exit 1
end
