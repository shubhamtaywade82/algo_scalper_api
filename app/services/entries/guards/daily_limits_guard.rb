# frozen_string_literal: true

module Entries
  module Guards
    class DailyLimitsGuard
      class << self
        def call(context)
          return EntryGuardPipeline::PASS if EntryGuard.daily_limits_allow_entry?(index_cfg: context[:index_cfg])

          { blocked: "daily loss/profit limits for #{context[:index_cfg][:key]}" }
        end
      end
    end
  end
end
