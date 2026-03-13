# frozen_string_literal: true

module Entries
  module Guards
    class TimeRegimeGuard
      class << self
        def call(context)
          return EntryGuardPipeline::PASS if EntryGuard.time_regime_allows_entry?(
            index_cfg: context[:index_cfg],
            pick: context[:pick],
            direction: context[:direction]
          )

          { blocked: "time regime rules for #{context[:index_cfg][:key]}" }
        end
      end
    end
  end
end
