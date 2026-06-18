# frozen_string_literal: true

module Entries
  module Guards
    class RsiBiasGuard
      include BaseGuard

      def self.call(context)
        return PASS if Signal::FastEntryMode.enabled?
        return PASS unless OptionsBuying::Mode.rsi_bias_enabled?

        index_key = context.dig(:index_cfg, :key)
        direction = context[:direction].to_s.downcase.to_sym
        return PASS unless index_key && %i[bullish bearish].include?(direction)

        bias = OptionsBuying::StateStore.rsi_bias(index_key)
        return PASS if bias.nil? || bias == :neutral

        if direction == :bullish && bias == :bearish
          return { blocked: "RSI bearish divergence conflicts with #{index_key} long (CE) entry" }
        end
        if direction == :bearish && bias == :bullish
          return { blocked: "RSI bullish divergence conflicts with #{index_key} short (PE) entry" }
        end

        PASS
      rescue StandardError => e
        # Advisory guard — fail open so a divergence-scan glitch never blocks entries.
        Rails.logger.warn("[RsiBiasGuard] #{e.class} - #{e.message}")
        PASS
      end
    end
  end
end
