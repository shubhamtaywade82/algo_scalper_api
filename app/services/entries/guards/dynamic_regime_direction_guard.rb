# frozen_string_literal: true

module Entries
  module Guards
    # Dynamically verifies 15-minute price structure regime (Market::MarketRegimeResolver)
    # before entry. Blocks BUY CE if 15m structure is bearish, and BUY PE if bullish.
    class DynamicRegimeDirectionGuard
      include BaseGuard

      def self.call(context)
        return PASS if context[:position_side].to_s == 'short'

        index_key = (context[:index_cfg] || {})[:key].to_s.upcase
        return PASS if index_key.blank?

        instrument = context[:instrument] || find_instrument(context[:index_cfg])
        return PASS unless instrument

        series_15m = instrument.candle_series(interval: '15')
        return PASS unless series_15m && series_15m.candles.size >= Market::MarketRegimeResolver::MIN_CANDLES

        regime = Market::MarketRegimeResolver.new(candles_15m: series_15m).call
        direction = context[:direction].to_s.downcase.to_sym
        bullish = %i[bullish long].include?(direction)

        if regime == :bearish && bullish
          { blocked: "Dynamic 15m structure is BEARISH — blocking counter-trend BUY CE on #{index_key}" }
        elsif regime == :bullish && !bullish
          { blocked: "Dynamic 15m structure is BULLISH — blocking counter-trend BUY PE on #{index_key}" }
        else
          PASS
        end
      rescue StandardError => e
        Rails.logger.warn("[DynamicRegimeDirectionGuard] Error: #{e.class} - #{e.message}")
        PASS
      end

      def self.find_instrument(index_cfg)
        IndexInstrumentCache.instance.get_or_fetch(index_cfg)
      rescue StandardError
        nil
      end
    end
  end
end
