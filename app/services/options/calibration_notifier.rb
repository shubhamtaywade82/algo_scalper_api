# frozen_string_literal: true

module Options
  # Sends Telegram notifications for calibration events.
  # Failures are silently rescued — never propagate to the job.
  class CalibrationNotifier
    def self.notify(symbol, run, auto_apply_result: nil)
      new.notify(symbol, run, auto_apply_result: auto_apply_result)
    end

    def self.notify_error(symbol, error)
      new.notify_error(symbol, error)
    end

    def self.notify_auto_apply_followup(symbol:, run:, auto_apply_result:)
      new.notify_auto_apply_followup(symbol: symbol, run: run, auto_apply_result: auto_apply_result)
    end

    def notify(symbol, run, auto_apply_result: nil)
      text = build_success_message(symbol, run, auto_apply_result: auto_apply_result)
      Notifications::TelegramNotifier.instance.send_message(text)
    rescue StandardError => e
      Rails.logger.error("[CalibrationNotifier] Telegram send failed: #{e.class} — #{e.message}")
    end

    def notify_auto_apply_followup(symbol:, run:, auto_apply_result:)
      return if auto_apply_result.blank?

      aa = AlgoConfig.fetch[:calibration]
      return unless aa.is_a?(Hash)

      nested = aa[:auto_apply]
      return unless nested.is_a?(Hash) && truthy?(nested[:enabled])

      text = build_auto_apply_followup_text(symbol, run, auto_apply_result, nested)
      return if text.blank?

      Notifications::TelegramNotifier.instance.send_message(text)
    rescue StandardError => e
      Rails.logger.error("[CalibrationNotifier] followup send failed: #{e.class} — #{e.message}")
    end

    def notify_error(symbol, error)
      text = "❌ Calibration failed: #{symbol}\n#{error.class}: #{error.message}"
      Notifications::TelegramNotifier.instance.send_message(text)
    rescue StandardError => e
      Rails.logger.error("[CalibrationNotifier] notify_error send failed: #{e.class} — #{e.message}")
    end

    private

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def build_success_message(symbol, run, auto_apply_result: nil)
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

      if run.applied_at.present?
        lines << "✅ *Auto-applied* at #{run.applied_at.in_time_zone('Asia/Kolkata').iso8601}"
      else
        lines << "Apply: POST /api/calibration_runs/#{run.id}/apply"
      end
      append_auto_apply_skip_line(lines, auto_apply_result)
      lines.join("\n")
    end

    def append_auto_apply_skip_line(lines, auto_apply_result)
      return if auto_apply_result.blank?
      return if auto_apply_result.suppress_notification
      return if auto_apply_result.applied
      return if auto_apply_result.reason.blank?

      aa = AlgoConfig.fetch[:calibration]
      return unless aa.is_a?(Hash)

      nested = aa[:auto_apply]
      return unless nested.is_a?(Hash) && truthy?(nested[:notify_on_skip])

      lines << "⚠️ *Auto-apply skipped:* #{auto_apply_result.reason}"
    end

    def build_auto_apply_followup_text(symbol, run, result, auto_apply_cfg)
      return nil if result.suppress_notification

      if result.applied
        "✅ *#{symbol}* calibration Run ##{run.id} auto-applied (#{run.strike_mode})"
      elsif truthy?(auto_apply_cfg[:notify_on_skip]) && result.reason.present?
        "⚠️ *#{symbol}* calibration Run ##{run.id} auto-apply skipped:\n#{result.reason}"
      end
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
