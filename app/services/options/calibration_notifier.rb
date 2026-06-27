# frozen_string_literal: true

module Options
  class CalibrationNotifier
    def self.notify(symbol, run)
      new.notify(symbol, run)
    end

    def self.notify_error(symbol, error)
      new.notify_error(symbol, error)
    end

    def notify(symbol, run)
      return unless telegram_enabled?

      Notifications::TelegramNotifier.instance.send_message(build_success_message(symbol, run))
    rescue StandardError => e
      Rails.logger.error("[CalibrationNotifier] Telegram send failed: #{e.class} - #{e.message}")
    end

    def notify_error(symbol, error)
      return unless telegram_enabled?

      message = "❌ Calibration failed: #{symbol}\n#{error.class}: #{error.message}"
      Notifications::TelegramNotifier.instance.send_message(message)
    rescue StandardError => e
      Rails.logger.error("[CalibrationNotifier] notify_error send failed: #{e.class} - #{e.message}")
    end

    private

    def telegram_enabled?
      defined?(Notifications::TelegramNotifier) &&
        Notifications::TelegramNotifier.instance.enabled?
    end

    def build_success_message(symbol, run)
      lines = ["📊 Calibration ready: #{symbol}"]
      lines << "Weeks: #{run.weeks_analyzed} | Mode: #{run.strike_mode}"
      lines << "⚠️ Regime shift: #{run.regime_reason}" if run.is_regime_shift

      patch = run.proposed_patch
      if patch.blank?
        lines << 'No significant config changes (<10% deviation from current)'
      else
        lines << 'Proposed changes:'
        flat_patch(patch).each { |key, value| lines << "  #{key}: #{value}" }
      end

      lines << "Apply: POST /api/calibration_runs/#{run.id}/apply"
      lines.join("\n")
    end

    def flat_patch(hash, prefix = nil)
      hash.flat_map do |key, value|
        full_key = prefix ? "#{prefix}.#{key}" : key.to_s
        value.is_a?(Hash) ? flat_patch(value, full_key) : [[full_key, value]]
      end
    end
  end
end
