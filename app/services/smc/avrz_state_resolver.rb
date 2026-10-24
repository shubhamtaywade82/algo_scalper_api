# frozen_string_literal: true

module Smc
  # AVRZ state from LTF {CandleSeries}.
  #
  # Error-handling review 2026-09 (wave 2): insufficient candle data and
  # detector failures used to be reported as :compressed — a real market state
  # that downstream maps to :execution_only (1-lot scalping allowed). An
  # UNKNOWN state must not be traded as if it were measured. Unknown now
  # returns nil, which {SmcPermissionResolver} treats as "no usable AVRZ
  # signal" and blocks.
  class AvrzStateResolver
    class << self
      # @param symbol [String, Symbol] index key (e.g. NIFTY)
      # @param ltf_series [CandleSeries, nil]
      # @return [Symbol, nil] :compressed, :expanding_early, etc.; nil when the
      #   state cannot be determined (insufficient data / detector failure)
      def resolve(symbol:, ltf_series:)
        key = symbol.to_s.strip.upcase
        candles = ltf_series&.candles || []
        if candles.size < 5
          Rails.logger.debug { "[Smc::AvrzStateResolver] insufficient LTF candles for #{key} (#{candles.size} < 5) — state unknown" }
          return nil
        end

        threshold = compression_threshold_pct(key)
        compressed = Entries::RangeUtils.compressed?(candles.last(6), threshold_pct: threshold)
        return :compressed if compressed

        rejection = Avrz::Detector.new(ltf_series).rejection?
        rejection ? :expanding_early : :compressed
      rescue StandardError => e
        Rails.logger.warn("[Smc::AvrzStateResolver] state resolution failed for #{key}: #{e.class} - #{e.message}")
        nil
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
