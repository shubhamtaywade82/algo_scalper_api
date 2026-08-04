# frozen_string_literal: true

module Agents
  # Solid Queue job that runs the AI trading orchestrator pipeline for one index.
  # Triggered on a recurring schedule (see config/recurring.yml) and also
  # callable manually:
  #
  #   Agents::TradingSignalJob.perform_later("NIFTY")
  #   Agents::TradingSignalJob.perform_later("BANKNIFTY")
  #
  class TradingSignalJob < ApplicationJob
    queue_as :background
    TAG = "[Agents::TradingSignalJob]"

    # @param index_key [String] e.g. "NIFTY", "BANKNIFTY", "SENSEX"
    # @param interval  [String] candle interval in minutes (default "5")
    def perform(index_key, interval = "5")
      unless market_open?
        Rails.logger.info("#{TAG} Market closed — skipping #{index_key}")
        return
      end

      Rails.logger.info("#{TAG} Running for #{index_key} (#{interval}m)")

      result = Agents::TradingOrchestrator.call(
        index_key: index_key,
        interval: interval
      )

      Rails.logger.info(
        "#{TAG} #{index_key} done — action=#{result[:action]} entered=#{result[:entered]} telegram=#{result[:telegram_sent]}"
      )
    rescue StandardError => e
      Rails.logger.error("#{TAG} #{index_key} unhandled error: #{e.class} - #{e.message}")
      raise # re-raise so Solid Queue marks the job as failed
    end

    private

    def market_open?

        Market::Calendar.market_open?
    rescue StandardError
        true

    end
  end
end
