# frozen_string_literal: true

module Entries
  module Guards
    class MaxConcurrentGuard
      class << self
        def call(context)
          max = context[:index_cfg][:max_concurrent_per_index]
          return EntryGuardPipeline::PASS unless max

          index_key = context[:index_cfg][:key].to_s
          current = PositionTracker.active.where("meta->>'index_key' = ?", index_key).count

          return EntryGuardPipeline::PASS if current < max.to_i

          { blocked: "max_concurrent_positions (#{current}/#{max}) for #{index_key}" }
        end
      end
    end
  end
end

