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

        avrz_state = resolve_avrz_state(symbol: key, ltf_series: ltf_series)

        smc_result = build_smc_result(htf: htf, mtf: mtf, ltf: ltf)
        avrz_result = { state: avrz_state }

        Smc::SmcPermissionResolver.resolve(smc_result: smc_result, avrz_result: avrz_result)
      rescue StandardError => e
        Rails.logger.error("[Trading::PermissionResolver] #{e.class} - #{e.message}")
        :blocked
      end

      private

      def resolve_avrz_state(symbol:, ltf_series:)
        candles = ltf_series&.candles || []
        return :dead if candles.size < 10

        compressed = Entries::RangeUtils.compressed?(candles.last(6), threshold_pct: compression_threshold_pct(symbol))
        return :compressed if compressed

        rejection = Avrz::Detector.new(ltf_series).rejection?
        rejection ? :expanding_early : :dead
      rescue StandardError
        :dead
      end

      # Index-specific compression thresholds (deterministic).
      # NOTE: These are conservative; if unsure => :compressed/:dead -> blocks scaling.
      def compression_threshold_pct(symbol)
        case symbol
        when 'SENSEX' then 0.04
        when 'NIFTY' then 0.06
        else 0.06
        end
      end

      def build_smc_result(htf:, mtf:, ltf:)
        htf_trend = htf.trend
        mtf_struct = mtf.structure.to_h
        ltf_struct = ltf.internal_structure.to_h

        structure_state =
          if htf_trend.to_sym == :range
            :range
          elsif %i[bullish bearish].include?(htf_trend.to_sym)
            :trend
          else
            :neutral
          end

        fvg_gaps = Array(ltf.fvg.to_h[:gaps])
        liquidity_h = ltf.liquidity.to_h

        {
          structure_state: structure_state,
          trend: htf_trend,
          bos_recent: (mtf_struct[:bos] == true),
          displacement: fvg_gaps.any?, # proxy: presence of FVG gaps
          liquidity_event_resolved: (liquidity_h[:sweep] == true),
          active_liquidity_trap: (liquidity_h[:equal_highs] == true || liquidity_h[:equal_lows] == true),
          trap_resolved: false,
          follow_through: (ltf_struct[:bos] == true)
        }
      rescue StandardError
        {}
      end
    end
  end
end

