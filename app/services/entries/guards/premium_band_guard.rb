# frozen_string_literal: true

module Entries
  module Guards
    # Blocks entries when option premium is outside the configured band for the index.
    # Prevents entering at extremes (too cheap = low delta, too expensive = high theta burn).
    class PremiumBandGuard
      class << self
        include BaseGuard

        def call(context)
          return PASS unless config_enabled?

          index_key = context.dig(:index_cfg, :key).to_s
          premium = context.dig(:pick, :ltp).to_f
          return PASS if index_key.empty? || premium.zero?

          band = premium_band_for(index_key)
          return PASS unless band

          min = band[:min].to_f
          max = band[:max].to_f
          return PASS if min.zero? && max.zero?

          if premium < min
            { blocked: "premium_band: #{index_key} premium ₹#{premium.round(2)} below min ₹#{min}" }
          elsif premium > max
            { blocked: "premium_band: #{index_key} premium ₹#{premium.round(2)} above max ₹#{max}" }
          else
            PASS
          end
        end

        private

        def config
          AlgoConfig.fetch || {}
        rescue StandardError
          {}
        end

        def config_enabled?
          # Enabled by default if any index has a premium_band configured
          indices.values.any? { |v| v.is_a?(Hash) && v[:premium_band].is_a?(Hash) }
        end

        def indices
          config[:indices] || {}
        end

        def premium_band_for(index_key)
          index_cfg = indices[index_key] || {}
          band = index_cfg[:premium_band]
          return band if band.is_a?(Hash)

          nil
        end
      end
    end
  end
end
