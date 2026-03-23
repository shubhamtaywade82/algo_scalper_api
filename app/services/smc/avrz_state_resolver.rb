# frozen_string_literal: true

module Smc
  # AVRZ state from LTF {CandleSeries} — same rules as {Trading::PermissionResolver}.
  class AvrzStateResolver
    class << self
      # @param symbol [String, Symbol] index key (e.g. NIFTY)
      # @param ltf_series [CandleSeries, nil]
      # @return [Symbol] :compressed, :expanding_early, etc.
      def resolve(symbol:, ltf_series:)
        key = symbol.to_s.strip.upcase
        candles = ltf_series&.candles || []
        return :compressed if candles.size < 5

        threshold = compression_threshold_pct(key)
        compressed = Entries::RangeUtils.compressed?(candles.last(6), threshold_pct: threshold)
        return :compressed if compressed

        rejection = Avrz::Detector.new(ltf_series).rejection?
        rejection ? :expanding_early : :compressed
      rescue StandardError
        :compressed
      end

      def compression_threshold_pct(symbol)
        case symbol
        when 'SENSEX' then 0.04
        when 'NIFTY' then 0.06
        else 0.06
        end
      end
    end
  end
end
