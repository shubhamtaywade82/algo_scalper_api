# frozen_string_literal: true

module OptionsBuying
  # Runs shortly before EOD square-off to tag high-ROI positional carries so the
  # EOD force-close and next-morning clear leave them open.
  class EodCarryJob < ApplicationJob
    queue_as :background

    def perform
      return unless Mode.positional_active?
      return if TradingSession::Service.market_closed?

      EodCarryManager.run!
    rescue StandardError => e
      Rails.logger.error("[OptionsBuying::EodCarryJob] #{e.class} - #{e.message}")
      raise
    end
  end
end
