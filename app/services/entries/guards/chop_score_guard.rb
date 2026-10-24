# frozen_string_literal: true

module Entries
  module Guards
    # Blocks noisy 1m Supertrend entries when objective chop conditions dominate.
    class ChopScoreGuard
      class << self
        include BaseGuard

        def call(context)
          # Selling exists specifically to trade the chop this guard filters out for buying.
          return PASS if context[:position_side].to_s == 'short'

          cfg = config
          return PASS unless cfg.fetch(:enabled, true)

          instrument = context[:instrument]
          return PASS unless instrument

          result = Entries::ChopScore.new(
            index_key: context.dig(:index_cfg, :key),
            series_1m: instrument.candle_series(interval: '1'),
            series_5m: instrument.candle_series(interval: '5'),
            series_15m: instrument.candle_series(interval: '15'),
            config: cfg
          ).call
          metadata = context[:entry_metadata]
          if metadata.nil? || metadata.frozen?
            metadata = context[:entry_metadata] = (metadata ? metadata.dup : {})
          end
          metadata[:chop_score] = result[:score]
          metadata[:chop_action] = result[:action].to_s

          return PASS unless result[:action] == :block

          { blocked: "chop_score=#{result[:score]}: #{result[:reasons].join('; ')}" }
        rescue StandardError => e
          Rails.logger.warn("[ChopScoreGuard] skipped: #{e.class} #{e.message}")
          PASS
        end

        private

        def config
          AlgoConfig.fetch.dig(:signals, :chop_score) || {}
        rescue StandardError
          {}
        end
      end
    end
  end
end
