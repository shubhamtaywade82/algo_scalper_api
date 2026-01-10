# frozen_string_literal: true

module Trading
  # ATR-based permission downgrader (safety-only).
  #
  # IMPORTANT:
  # - This does NOT compute ATR. It only consumes ATR values supplied by the caller.
  # - This must NEVER upgrade permission, never change direction, never create trades.
  # - If inputs are ambiguous/missing, return :blocked (capital protection).
  class AtrPermissionModifier
    PERMISSIONS = %i[blocked execution_only scale_ready full_deploy].freeze

    class << self
      # Apply ATR-based safety downgrades to an existing permission.
      #
      # @param permission [Symbol, String]
      # @param atr_current [Numeric]
      # @param atr_session_median [Numeric]
      # @param atr_slope [Numeric] slope over recent window (<= 0 implies non-expanding volatility)
      # @return [Symbol] modified permission or :blocked
      def apply(permission:, atr_current:, atr_session_median:, atr_slope:)
        p = normalize_permission(permission)
        return :blocked unless PERMISSIONS.include?(p)
        return :blocked if p == :blocked

        unless numeric_finite?(atr_current) && numeric_finite?(atr_session_median) && numeric_finite?(atr_slope)
          return :blocked
        end
        return :blocked unless atr_current.positive? && atr_session_median.positive?

        # Rule 1 (first):
        # If atr_current < atr_session_median:
        # - full_deploy -> scale_ready
        # - scale_ready -> execution_only
        # - execution_only -> execution_only
        p = downgrade_for_low_atr(p) if atr_current < atr_session_median

        # Rule 2 (second):
        # If atr_slope <= 0:
        # - scale_ready -> execution_only
        # - full_deploy -> scale_ready
        p = downgrade_for_non_positive_slope(p) if atr_slope <= 0

        # Rule 3 (implicit safety): never upgrade.
        p
      end

      private

      def downgrade_for_low_atr(permission)
        case permission
        when :full_deploy then :scale_ready
        when :scale_ready then :execution_only
        when :execution_only then :execution_only
        else :blocked
        end
      end

      def downgrade_for_non_positive_slope(permission)
        case permission
        when :full_deploy then :scale_ready
        when :scale_ready then :execution_only
        when :execution_only then :execution_only
        else :blocked
        end
      end

      def normalize_permission(permission)
        return :blocked if permission.nil?

        if permission.is_a?(String)
          v = permission.strip.downcase
          return :blocked if v == ''

          return v.to_sym
        end

        permission.is_a?(Symbol) ? permission : :blocked
      end

      def numeric_finite?(value)
        value.is_a?(Numeric) && value.finite?
      rescue StandardError
        false
      end
    end
  end
end
