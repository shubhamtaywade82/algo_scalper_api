# frozen_string_literal: true

# Start ATM options service if WebSocket is enabled
Rails.application.config.after_initialize do
  if Rails.env.development? && Rails.application.config.x.dhanhq&.ws_enabled
    Rails.logger.info("[AtmOptions] Starting ATM options service")
    begin
      Live::AtmOptionsService.instance.start!
    rescue StandardError => e
      Rails.logger.error("[AtmOptions] Failed to start: #{e.class} - #{e.message}")
      Rails.logger.error("[AtmOptions] Backtrace: #{e.backtrace.first(5).join(', ')}")
    end
  else
    Rails.logger.info("[AtmOptions] Not starting - WebSocket disabled or not in development")
  end
end
