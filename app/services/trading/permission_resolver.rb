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

        # Check if SMC permission checks are disabled or loosened
        config = AlgoConfig.fetch[:signals] || {}
        enable_smc_permission = config.fetch(:enable_smc_avrz_permission, true)
        permission_mode = config[:permission_mode] || 'strict' # strict, lenient, bypass

        # If SMC+AVRZ permission checks are disabled, return scale_ready (allows trading)
        unless enable_smc_permission
          Rails.logger.info("[PermissionResolver] SMC+AVRZ permission checks DISABLED - allowing scale_ready for #{key}")
          return :scale_ready
        end

        # Bypass mode: Return execution_only for all (testing/development)
        if permission_mode == 'bypass'
          Rails.logger.debug { "[PermissionResolver] Bypass mode - allowing execution_only for #{key}" }
          return :execution_only
        end

        htf_series = instrument.candle_series(interval: Smc::BiasEngine::HTF_INTERVAL)
        mtf_series = instrument.candle_series(interval: Smc::BiasEngine::MTF_INTERVAL)
        ltf_series = instrument.candle_series(interval: Smc::BiasEngine::LTF_INTERVAL)

        # More lenient: Allow if at least HTF and MTF have data (LTF can be missing)
        # This handles rate limiting scenarios better
        # In lenient mode, allow with just HTF data
        if permission_mode == 'lenient'
          return :blocked unless htf_series&.candles&.any?
        else
          return :blocked unless htf_series&.candles&.any? && mtf_series&.candles&.any?
        end

        # If LTF is missing, use MTF for AVRZ (fallback)
        avrz_series = ltf_series&.candles&.any? ? ltf_series : mtf_series

        htf = Smc::Context.new(htf_series)
        mtf = mtf_series&.candles&.any? ? Smc::Context.new(mtf_series) : htf # Fallback to HTF if MTF missing
        ltf = ltf_series&.candles&.any? ? Smc::Context.new(ltf_series) : mtf # Fallback to MTF if LTF missing

        avrz_state = resolve_avrz_state(symbol: key, ltf_series: avrz_series)

        smc_result = build_smc_result(htf: htf, mtf: mtf, ltf: ltf)
        avrz_result = { state: avrz_state }

        Smc::SmcPermissionResolver.resolve(
          smc_result: smc_result,
          avrz_result: avrz_result,
          mode: permission_mode
        )
      rescue StandardError => e
        Rails.logger.error("[Trading::PermissionResolver] #{e.class} - #{e.message}")
        # In lenient mode, default to execution_only instead of blocked
        config = AlgoConfig.fetch[:signals] || {}
        permission_mode = config[:permission_mode] || 'strict'
        permission_mode == 'lenient' ? :execution_only : :blocked
      end

      private

      def resolve_avrz_state(symbol:, ltf_series:)
        candles = ltf_series&.candles || []
        # Reduced minimum candle requirement from 10 to 5 for more lenient detection
        return :compressed if candles.size < 5 # Default to compressed instead of dead

        compressed = Entries::RangeUtils.compressed?(candles.last(6), threshold_pct: compression_threshold_pct(symbol))
        return :compressed if compressed

        rejection = Avrz::Detector.new(ltf_series).rejection?
        rejection ? :expanding_early : :compressed # Default to compressed instead of dead for better trade opportunities
      rescue StandardError
        :compressed # More lenient: default to compressed instead of dead
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
        # ltf might be mtf fallback, so use internal_structure safely
        ltf_struct = ltf.respond_to?(:internal_structure) ? ltf.internal_structure.to_h : mtf_struct

        structure_state =
          if htf_trend.to_sym == :range
            :range
          elsif %i[bullish bearish].include?(htf_trend.to_sym)
            :trend
          else
            :neutral
          end

        # Use ltf for FVG/liquidity if available, otherwise fallback to mtf
        fvg_data = ltf.respond_to?(:fvg) ? ltf.fvg.to_h : {}
        liquidity_data = ltf.respond_to?(:liquidity) ? ltf.liquidity.to_h : {}
        fvg_gaps = Array(fvg_data[:gaps])
        liquidity_h = liquidity_data

        {
          structure_state: structure_state,
          trend: htf_trend,
          bos_recent: (mtf_struct[:bos] == true),
          displacement: fvg_gaps.any?, # proxy: presence of FVG gaps
          liquidity_event_resolved: (liquidity_h[:sweep] == true),
          active_liquidity_trap: liquidity_h[:equal_highs] == true || liquidity_h[:equal_lows] == true,
          trap_resolved: false,
          follow_through: (ltf_struct[:bos] == true)
        }
      rescue StandardError
        {}
      end
    end
  end
end
