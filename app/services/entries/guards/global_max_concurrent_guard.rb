# frozen_string_literal: true

module Entries
  module Guards
    # Portfolio-level max concurrent positions guard.
    # Blocks new entries when total active positions across all indices
    # exceeds global_max_concurrent_positions, or when same-direction positions
    # exceed max_concurrent_same_direction to prevent cross-index correlation risk.
    class GlobalMaxConcurrentGuard
      class << self
        def call(context)
          trade_limits = AlgoConfig.fetch[:trade_limits] || {}
          global_max = trade_limits[:global_max_concurrent_positions]

          if global_max
            current_total = PositionTracker.active.count
            if current_total >= global_max.to_i
              return { blocked: "global_max_concurrent_positions (#{current_total}/#{global_max})" }
            end
          end

          max_same_dir = trade_limits[:max_concurrent_same_direction]
          if max_same_dir && (side = candidate_side(context)).present?
            same_dir_count = PositionTracker.active.where(side: side).count
            if same_dir_count >= max_same_dir.to_i
              return { blocked: "max_concurrent_same_direction (#{same_dir_count}/#{max_same_dir} for #{side})" }
            end
          end

          EntryGuardPipeline::PASS
        end

        private

        # Resolves candidate position side ('long_ce', 'long_pe', 'short_ce', 'short_pe')
        # to enforce directional portfolio concentration limits.
        def candidate_side(context)
          return context[:side].to_s if context[:side].present?
          return nil if context[:direction].blank?

          dir_sym = context[:direction].to_s.downcase.to_sym
          bullish = %i[bullish long].include?(dir_sym)
          if context[:position_side].to_s == 'short'
            bullish ? 'short_pe' : 'short_ce'
          else
            bullish ? 'long_ce' : 'long_pe'
          end
        end
      end
    end
  end
end
