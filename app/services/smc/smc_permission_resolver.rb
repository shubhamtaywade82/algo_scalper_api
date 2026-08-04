# frozen_string_literal: true

module Smc
  # Pure interpretation layer: converts existing SMC + AVRZ structured outputs into
  # capital deployment permission levels.
  #
  # IMPORTANT:
  # - No side effects (no DB, no logging, no time logic).
  # - Deterministic output.
  # - If anything is ambiguous/missing => default to :blocked (capital protection).
  class SmcPermissionResolver
    PERMISSIONS = %i[blocked execution_only scale_ready full_deploy].freeze

    class << self
      # Convert SMC + AVRZ outputs to a permission level.
      #
      # @param smc_result [Hash, #to_h] existing SMC output (unchanged)
      # @param avrz_result [Hash, #to_h] existing AVRZ output (unchanged)
      # @param mode [String] Permission mode: 'strict', 'lenient', or 'bypass'
      # @return [Symbol] one of: :blocked, :execution_only, :scale_ready, :full_deploy
      def resolve(smc_result:, avrz_result:, mode: 'strict')
        smc = NormalizedSmc.new(smc_result)
        avrz = NormalizedAvrz.new(avrz_result)

        # ---------------- HARD BLOCK (:blocked) ----------------
        # STRICT:
        # - SMC structure state is :neutral (always block - no direction)
        # - AVRZ state == :dead only blocks if we have very few candles (< 5)
        #   (With our lenient AVRZ detection, :dead should be rare)
        return :blocked if smc.structure_state == :neutral

        # Range markets: Allow execution_only if displacement is present
        # In lenient mode: Allow range markets even without displacement
        if smc.structure_state == :range
          if smc.displacement?
            Rails.logger.debug('[SmcPermissionResolver] Range market with displacement - allowing execution_only')
            return :execution_only
          elsif mode == 'lenient'
            Rails.logger.debug('[SmcPermissionResolver] Lenient mode - allowing range market without displacement')
            return :execution_only
          end
          Rails.logger.debug('[SmcPermissionResolver] Range market blocked - no displacement')
          return :blocked
        end

        # Trend markets: Require BOS for any permission
        # In lenient mode: Allow trend markets even without BOS (if displacement present)
        unless smc.bos_recent?
          if mode == 'lenient' && smc.displacement?
            Rails.logger.debug('[SmcPermissionResolver] Lenient mode - allowing trend market without BOS (has displacement)')
            return :execution_only
          end
          return :blocked
        end

        # ---------------- FULL DEPLOY (:full_deploy) ----------------
        # STRICT:
        # - SMC shows trap resolution OR clean BOS + follow-through
        # - Displacement confirmed
        # - AVRZ state == :expanding
        #
        # NOTE: This is intentionally rare. It's where you allow full capital
        # deployment because structure+expansion are both confirmed.
        if avrz.state == :expanding &&
           smc.displacement? &&
           (smc.trap_resolved? || (smc.bos_recent? && smc.follow_through?))
          return :full_deploy
        end

        # ---------------- SCALE READY (:scale_ready) ----------------
        # STRICT:
        # - SMC shows BOS + displacement
        # - No active liquidity trap
        # - AVRZ state == :expanding_early
        if avrz.state == :expanding_early &&
           smc.displacement? &&
           !smc.active_liquidity_trap?
          return :scale_ready
        end

        # ---------------- EXECUTION ONLY (:execution_only) ----------------
        # STRICT:
        # - SMC structure is valid (trend exists)
        # - BUT no displacement OR no resolved liquidity event
        # - AVRZ state == :compressed
        #
        # NOTE: This permits *1-lot scalping* (execution), but blocks scaling.
        # It's designed to let your 1m execution engine participate safely while
        # the HTF permission has not upgraded into expansion/clean resolution yet.
        if avrz.state == :compressed &&
           smc.trend_valid? &&
           (!smc.displacement? || !smc.liquidity_event_resolved?)
          return :execution_only
        end

        # Lenient mode fallback: If we have a trend market with BOS but don't meet other criteria,
        # still allow execution_only
        if mode == 'lenient' && smc.structure_state == :trend && smc.bos_recent?
          Rails.logger.debug('[SmcPermissionResolver] Lenient mode - allowing trend market with BOS as execution_only')
          return :execution_only
        end

        :blocked
      end
    end

    # -------- Normalization (no format changes to existing engines) ----------

    class NormalizedSmc
      def initialize(raw)
        @raw = if raw.respond_to?(:to_h)
                 raw.to_h
               else
                 (raw.is_a?(Hash) ? raw : {})
               end
      end

      def structure_state
        # Default to :neutral if unknown (capital protection).
        sym(
          value(:structure_state) ||
          dig(:structure_state, :state) ||
          dig(:structure, :state) ||
          dig(:structure, :structure_state) ||
          dig(:structure_state)
        ) || :neutral
      end

      def bos_recent?
        bool(
          value(:bos_recent) ||
          value(:bos_detected_recently) ||
          value(:bos) ||
          dig(:structure, :bos_recent) ||
          dig(:structure, :bos) ||
          dig(:bos, :recent) ||
          dig(:bos, :present)
        ) == true
      end

      def displacement?
        bool(
          value(:displacement) ||
          dig(:displacement, :present) ||
          dig(:displacement, :confirmed)
        ) == true
      end

      def liquidity_event_resolved?
        bool(
          value(:liquidity_event_resolved) ||
          value(:resolved_liquidity_event) ||
          value(:liquidity_resolved) ||
          dig(:liquidity_event, :resolved) ||
          dig(:liquidity_sweep, :resolved) ||
          dig(:liquidity, :resolved)
        ) == true
      end

      def active_liquidity_trap?
        # If unknown, treat as active (so scale_ready cannot pass accidentally).
        v =
          value(:active_liquidity_trap) ||
          value(:liquidity_trap_active) ||
          value(:liquidity_trap) ||
          dig(:trap, :active) ||
          dig(:liquidity_trap, :active) ||
          dig(:liquidity, :trap_active) ||
          dig(:liquidity, :trap)

        v.nil? || (bool(v) == true)
      end

      def trap_resolved?
        bool(
          value(:trap_resolved) ||
          value(:liquidity_trap_resolved) ||
          dig(:trap, :resolved) ||
          dig(:liquidity_trap, :resolved)
        ) == true
      end

      def follow_through?
        bool(
          value(:follow_through) ||
          value(:bos_follow_through) ||
          value(:clean_follow_through) ||
          dig(:bos, :follow_through) ||
          dig(:bos, :clean_follow_through)
        ) == true
      end

      def trend_valid?
        trend = sym(
          value(:trend) ||
          dig(:structure, :trend) ||
          dig(:structure, :direction) ||
          dig(:trend, :direction)
        )

        trend.in?(%i[bullish bearish])
      end

      private

      def value(key)
        @raw[key]
      end

      def dig(*path)
        path.reduce(@raw) { |acc, k| acc.is_a?(Hash) ? acc[k] : nil }
      end

      def sym(v)
        return v if v.is_a?(Symbol)
        return v.to_s.strip.downcase.to_sym if v.is_a?(String) && v.strip != ''

        nil
      end

      def bool(v)
        return v if [true, false].include?(v)
        return true if v.is_a?(String) && v.strip.downcase == 'true'
        return false if v.is_a?(String) && v.strip.downcase == 'false'

        nil
      end
    end

    class NormalizedAvrz
      def initialize(raw)
        @raw = if raw.respond_to?(:to_h)
                 raw.to_h
               else
                 (raw.is_a?(Hash) ? raw : {})
               end
      end

      def state
        sym(@raw[:state] || @raw[:avrz_state] || @raw.dig(:avrz, :state))
      end

      private

      def sym(v)
        return v if v.is_a?(Symbol)
        return v.to_s.strip.downcase.to_sym if v.is_a?(String) && v.strip != ''

        nil
      end
    end
  end
end
