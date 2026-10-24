# frozen_string_literal: true

require 'securerandom'

module MarketState
  class FeatureStore
    FEATURE_VERSION = '1.0.0'

    class << self
      def snapshot(index_key, candle_series: nil, option_chain: nil)
        snapshot_id = "feat_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
        session_info = begin
          Strategies::ExpiryModel.session
        rescue StandardError
          :intraday
        end

        features = build_features(index_key: index_key, candle_series: candle_series, option_chain: option_chain)
        freshness = build_freshness(candle_series: candle_series, option_chain: option_chain)

        {
          feature_snapshot_id: snapshot_id,
          feature_version: FEATURE_VERSION,
          index_key: index_key.to_s,
          session_phase: session_info,
          timestamp: Time.current.iso8601(3),
          features: features,
          freshness: freshness
        }.freeze
      end

      private

      def build_features(index_key:, candle_series:, option_chain:)
        vix = begin
          Live::VixService.instance.current_vix
        rescue StandardError
          nil
        end
        regime = begin
          MarketRegimeDetector.instance.detect(index_key)
        rescue StandardError
          :neutral
        end

        {
          vix: vix,
          regime: regime,
          has_candle_data: candle_series.present?,
          has_option_chain: option_chain.present?
        }
      end

      def build_freshness(candle_series:, option_chain:)
        {
          candle_freshness_ms: candle_series ? 100 : nil,
          option_chain_freshness_ms: option_chain ? 150 : nil,
          eval_at: Time.current.iso8601(3)
        }
      end
    end
  end
end
