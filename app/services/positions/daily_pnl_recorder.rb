# frozen_string_literal: true

module Positions
  class DailyPnlRecorder < ApplicationService
    def initialize(tracker:)
      @tracker = tracker
    end

    def call
      return unless tracker.exited? && tracker.last_pnl_rupees.present?

      pnl_amount = tracker.last_pnl_rupees.to_f
      return if pnl_amount.zero?

      daily_limits = Live::DailyLimits.new
      pnl_amount.positive? ? record_profit(daily_limits, pnl_amount) : record_loss(daily_limits, pnl_amount)
    rescue StandardError => e
      Rails.logger.error("[Positions::DailyPnlRecorder] #{e.class} - #{e.message}")
    end

    private

    attr_reader :tracker

    def index_key
      tracker.index_key.presence || tracker.symbol || 'UNKNOWN'
    end

    def record_profit(daily_limits, pnl_amount)
      daily_limits.record_profit(index_key: index_key, amount: pnl_amount)
    end

    def record_loss(daily_limits, pnl_amount)
      daily_limits.record_loss(index_key: index_key, amount: pnl_amount.abs)
    end
  end
end
