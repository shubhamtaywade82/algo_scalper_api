# frozen_string_literal: true

module Options
  # Sends Telegram notifications for calibration events.
  # Failures are silently rescued — never propagate to the job.
  class CalibrationNotifier
    def self.notify(symbol, run)
      new.notify(symbol, run)
    end

    def self.notify_error(symbol, error)
      new.notify_error(symbol, error)
    end

    def notify(symbol, run)
      text = build_success_message(symbol, run)
      Notifications::TelegramNotifier.instance.send_message(text)
    rescue StandardError => e
      Rails.logger.error("[CalibrationNotifier] Telegram send failed: #{e.class} — #{e.message}")
    end

    def notify_error(symbol, error)
      text = "❌ Calibration failed: #{symbol}\n#{error.class}: #{error.message}"
      Notifications::TelegramNotifier.instance.send_message(text)
    rescue StandardError => e
      Rails.logger.error("[CalibrationNotifier] notify_error send failed: #{e.class} — #{e.message}")
    end

    private

    def build_success_message(symbol, run)
      lines = ["📊 *Calibration ready:* #{symbol}"]
      lines << "Weeks: #{run.weeks_analyzed} | Mode: #{run.strike_mode}"
      lines << "⚠️ *Regime shift:* #{run.regime_reason}" if run.is_regime_shift

      patch = run.proposed_patch
      if patch.empty?
        lines << "_No significant config changes (<10% deviation from current)_"
      else
        lines << "*Proposed changes:*"
        flat_patch(patch).each { |k, v| lines << "  #{k}: #{v}" }
      end

      lines << "Apply: POST /api/calibration_runs/#{run.id}/apply"
      lines.join("\n")
    end

    # Flattens nested hash to dot-notation keys for display
    def flat_patch(hash, prefix = nil)
      hash.flat_map do |k, v|
        full_key = prefix ? "#{prefix}.#{k}" : k.to_s
        v.is_a?(Hash) ? flat_patch(v, full_key) : [[full_key, v]]
      end
    end
  end
end
