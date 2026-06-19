# frozen_string_literal: true

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
      Rails.logger.error("[WeeklyCalibrationJob] #{sym} failed: #{e.class} - #{e.message}")
      Options::CalibrationNotifier.notify_error(sym, e)
    end
  end
end
