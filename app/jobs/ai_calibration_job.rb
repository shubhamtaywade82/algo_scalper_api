# frozen_string_literal: true

# Solid Queue background job for AI-driven trading calibration.
#
# Runs the Ai::Calibration::Runner pipeline for one or all symbols.
# Produces a CalibrationRun record — does NOT auto-apply changes.
# A human must inspect the proposed_patch and call run.apply!() to activate.
#
# Usage:
#   AiCalibrationJob.perform_later                   # all symbols, 30 days
#   AiCalibrationJob.perform_later('NIFTY')          # single symbol
#   AiCalibrationJob.perform_later('NIFTY', 14)      # last 14 days of trades
#
# Scheduling (add to config/recurring.yml):
#   ai_calibration_weekly:
#     class: AiCalibrationJob
#     queue: background
#     schedule: every Sunday at 07:00 IST
class AiCalibrationJob < ApplicationJob
  queue_as :background

  SYMBOLS = %w[NIFTY BANKNIFTY SENSEX].freeze

  def perform(symbol = nil, days = 30)
    symbols = symbol ? [symbol.to_s.upcase] : SYMBOLS

    symbols.each do |sym|
      Rails.logger.info("[AiCalibrationJob] Starting calibration for #{sym} (#{days} days)")

      run = Ai::Calibration::Runner.call(symbol: sym, days: days)

      if run
        Rails.logger.info(
          "[AiCalibrationJob] #{sym}: CalibrationRun ##{run.id} created. " \
          "Review with: CalibrationRun.find(#{run.id}).proposed_patch"
        )
      else
        Rails.logger.info("[AiCalibrationJob] #{sym}: No actionable calibration produced")
      end
    rescue Ai::Calibration::Runner::InsufficientDataError => e
      Rails.logger.warn("[AiCalibrationJob] #{sym}: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("[AiCalibrationJob] #{sym}: #{e.class} — #{e.message}")
    end
  end
end
