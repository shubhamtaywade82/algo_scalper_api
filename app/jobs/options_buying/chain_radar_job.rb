# frozen_string_literal: true

module OptionsBuying
  class ChainRadarJob < ApplicationJob
    queue_as :background

    def perform
      return unless Mode.chain_radar_enabled?
      return if TradingSession::Service.market_closed?

      IndexConfigLoader.load_indices.each do |idx_cfg|
        ChainRadar.scan!(idx_cfg[:key])
      end
    rescue StandardError => e
      Rails.logger.error("[OptionsBuying::ChainRadarJob] #{e.class} - #{e.message}")
      raise
    end
  end
end
