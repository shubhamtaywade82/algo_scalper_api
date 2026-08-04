# frozen_string_literal: true

module Trading
  # Deterministic permission resolver for options buying.
  #
  # IMPORTANT:
  # - This is a HARD rules layer. It must not create trades or override DirectionGate/MarketRegime.
  # - If anything is ambiguous/missing => :blocked (capital protection).
  #
  # It converts existing SMC contexts + AVRZ heuristics into the same permission
  # vocabulary used by the system: :blocked, :execution_only, :scale_ready, :full_deploy.
  class PermissionResolver
    class << self
      # @param symbol [String, Symbol]
      # @param instrument [Instrument]
      # @return [Symbol]
      def resolve(symbol:, instrument:)
        key = symbol.to_s.strip.upcase
        return :blocked unless instrument

        htf_series = instrument.candle_series(interval: Smc::BiasEngine::HTF_INTERVAL)
        mtf_series = instrument.candle_series(interval: Smc::BiasEngine::MTF_INTERVAL)
        ltf_series = instrument.candle_series(interval: Smc::BiasEngine::LTF_INTERVAL)
        return :blocked unless htf_series&.candles&.any? && mtf_series&.candles&.any? && ltf_series&.candles&.any?

        htf = Smc::Context.new(htf_series)
        mtf = Smc::Context.new(mtf_series)
        ltf = Smc::Context.new(ltf_series)

        avrz_state = Smc::AvrzStateResolver.resolve(symbol: key, ltf_series: avrz_series)

        smc_result = Smc::PermissionSnapshot.from_contexts(htf: htf, mtf: mtf, ltf: ltf)
        avrz_result = { state: avrz_state }

        Smc::SmcPermissionResolver.resolve(smc_result: smc_result, avrz_result: avrz_result)
      rescue StandardError => e
        Rails.logger.error("[Trading::PermissionResolver] #{e.class} - #{e.message}")
        :blocked
      end
    end
  end
end
