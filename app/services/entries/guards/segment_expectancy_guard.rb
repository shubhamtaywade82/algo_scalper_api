# frozen_string_literal: true

module Entries
  module Guards
    # Blocks new entries into (index, session-regime) segments that the bot's own
    # closed-trade history shows are statistically negative-edge — see
    # Trading::SegmentExpectancyAnalyzer for the realized-expectancy computation.
    # A no-op for segments with too little history to be meaningful (cold start)
    # or with merely break-even/positive realized expectancy.
    class SegmentExpectancyGuard
      class << self
        include BaseGuard

        def call(context)
          return PASS unless config_enabled?

          index_key = context.dig(:index_cfg, :key).to_s
          return PASS if index_key.empty?

          regime = Live::TimeRegimeService.instance.current_regime
          return PASS unless Trading::SegmentExpectancyAnalyzer.instance.negative_edge?(index_key: index_key, regime: regime)

          { blocked: "segment expectancy guard: #{index_key}/#{regime} has shown a negative realized edge recently" }
        rescue StandardError => e
          Rails.logger.warn("[SegmentExpectancyGuard] error: #{e.class} - #{e.message}")
          PASS
        end

        private

        def config
          AlgoConfig.fetch[:segment_expectancy_guard] || {}
        rescue StandardError
          {}
        end

        def config_enabled?
          config[:enabled] == true
        end
      end
    end
  end
end
