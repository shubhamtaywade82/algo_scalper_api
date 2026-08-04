# frozen_string_literal: true

# Solid Queue weekly job for automated options calibration.
# Runs every Sunday at 6:00 AM IST in production.
#
# Positional defaults (not keyword args) — Ruby 3.3 Active Job
# serialisation raises ArgumentError on keyword-only signatures.
#
# Usage:
#   WeeklyCalibrationJob.perform_later           # both symbols (scheduled)
#   WeeklyCalibrationJob.perform_later('NIFTY')  # manual single-symbol run
class WeeklyCalibrationJob < ApplicationJob
  queue_as :background

  def perform(symbol = nil, weeks = 52)
    symbols = symbol ? [symbol.to_s.upcase] : %w[NIFTY SENSEX]

    symbols.each do |sym|
      run = Options::AutoCalibrator.call(symbol: sym, weeks: weeks)
      if run
        run.propose_config!
        Options::CalibrationNotifier.notify(sym, run)
      else
        Options::CalibrationNotifier.notify_error(
          sym,
          RuntimeError.new('AutoCalibrator returned nil — all DhanHQ fetches failed')
        )
      end
    rescue StandardError => e
      Rails.logger.error("[WeeklyCalibrationJob] #{sym} failed: #{e.class} — #{e.message}")
      Options::CalibrationNotifier.notify_error(sym, e)
    end
  end
end
