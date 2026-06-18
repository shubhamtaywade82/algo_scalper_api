# frozen_string_literal: true

module OptionsBuying
  class DailyMetricsJob < ApplicationJob
    queue_as :background

    def perform
      IndexConfigLoader.load_indices.each do |idx_cfg|
        seed_daily_atr(idx_cfg)
      end
    rescue StandardError => e
      Rails.logger.error("[OptionsBuying::DailyMetricsJob] #{e.class} - #{e.message}")
      raise
    end

    private

    def seed_daily_atr(idx_cfg)
      instrument = Instrument.find_by_sid_and_segment(
        security_id: idx_cfg[:sid],
        segment_code: idx_cfg[:segment],
        symbol_name: idx_cfg[:key]
      )
      return unless instrument

      atr = OptionsBuying::ATRCompressionChecker.compute_daily_atr_for(instrument)
      return unless atr&.positive?

      StateStore.set_daily_atr(idx_cfg[:key], atr)
      Rails.logger.info("[OptionsBuying::DailyMetricsJob] Seeded ATR #{idx_cfg[:key]}=#{atr.round(2)}")
    end
  end
end
