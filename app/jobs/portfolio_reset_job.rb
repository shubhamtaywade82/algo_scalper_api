# frozen_string_literal: true

class PortfolioResetJob < ApplicationJob
  queue_as :background

  def perform
    Rails.logger.info("[PortfolioResetJob] Starting daily portfolio PnL reset")
    Portfolio::DrawdownGuard.reset_day!
    Rails.logger.info("[PortfolioResetJob] Daily portfolio PnL reset completed")
  rescue StandardError => e
    Rails.logger.error("[PortfolioResetJob] Failed to reset portfolio PnL: #{e.class} - #{e.message}")
    Notifications::TelegramNotifier.instance.notify_error("#{e.class} - #{e.message}", context: 'PortfolioResetJob')
  end
end
