# frozen_string_literal: true

module Trading
  # Mechanical mapping from permission level -> execution/scaling/exit policy.
  #
  # This is intentionally NOT strategic:
  # - No indicators, no structure evaluation, no momentum inference.
  # - No order placement, no broker access, no instrument awareness.
  #
  # It only describes allowed behavior to be *consumed* by orchestration layers.
  class PermissionExecutionPolicy
    class << self
      # @param permission [Symbol, String, nil]
      # @return [Hash] frozen policy hash (and nested arrays/hashes are frozen)
      def for(permission:)
        key = normalize_permission(permission)
        policy = POLICIES.fetch(key, POLICIES[:blocked])
        deep_dup(policy) # return a fresh, immutable object each call
      end

      # Deep freeze helper - must be public to be called during constant definition
      def deep_freeze(obj)
        case obj
        when Hash
          obj.each_value { |v| deep_freeze(v) }
        when Array
          obj.each { |v| deep_freeze(v) }
        end
        obj.freeze
      end

      private

      def normalize_permission(permission)
        return :blocked if permission.nil?

        if permission.is_a?(String)
          normalized = permission.strip.downcase
          return :blocked if normalized == ''

          return normalized.to_sym
        end

        permission.is_a?(Symbol) ? permission : :blocked
      end

      def deep_dup(obj)
        case obj
        when Hash
          obj.transform_values { |v| deep_dup(v) }.freeze
        when Array
          obj.map { |v| deep_dup(v) }.freeze
        else
          obj # primitives are already frozen in our constants
        end
      end
    end

    # NOTE: :execution_only allows 1-lot scalping but blocks scaling.
    # This prevents capital deployment during compression while still allowing
    # micro-execution to gather/monetize small moves without account bleed.
    #
    # NOTE: :full_deploy is intentionally rare.
    # This is where scaling is a *reward* for confirmed expansion and clean structure.
    POLICIES = {
      blocked: deep_freeze(
        {
          max_lots: 0,
          allow_scaling: false,
          max_scale_steps: 0,
          profit_targets: [],
          hard_stop_pct: 0.0,
          time_stop_candles: 0,
          allow_runner: false
        }
      ),
      execution_only: deep_freeze(
        {
          max_lots: 1,
          allow_scaling: false,
          max_scale_steps: 0,
          profit_targets: [4, 6],
          hard_stop_pct: 0.20,
          time_stop_candles: 2,
          allow_runner: false
        }
      ),
      scale_ready: deep_freeze(
        {
          max_lots: 2,
          allow_scaling: true,
          max_scale_steps: 1,
          profit_targets: [6, 10],
          hard_stop_pct: 0.22,
          time_stop_candles: 3,
          allow_runner: false
        }
      ),
      full_deploy: deep_freeze(
        {
          max_lots: 4,
          allow_scaling: true,
          max_scale_steps: 3,
          profit_targets: [6, 10, 15],
          hard_stop_pct: 0.25,
          time_stop_candles: 3,
          allow_runner: true
        }
      )
    }.freeze
  end
end
