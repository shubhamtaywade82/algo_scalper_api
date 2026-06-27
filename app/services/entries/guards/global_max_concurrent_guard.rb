# frozen_string_literal: true

module Entries
  module Guards
    # Portfolio-level max concurrent positions guard.
    # Blocks new entries when total active positions across all indices
    # exceeds the global_max_concurrent_positions limit.
    class GlobalMaxConcurrentGuard
      class << self
        def call(context)
          max = AlgoConfig.fetch.dig(:trade_limits, :global_max_concurrent_positions)
          return EntryGuardPipeline::PASS unless max

          current = PositionTracker.active.count

          return EntryGuardPipeline::PASS if current < max.to_i

          { blocked: "global_max_concurrent_positions (#{current}/#{max})" }
        end
      end
    end
  end
end