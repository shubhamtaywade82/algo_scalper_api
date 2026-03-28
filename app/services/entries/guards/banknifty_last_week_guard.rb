# frozen_string_literal: true

module Entries
  module Guards
    class BankniftyLastWeekGuard
      class << self
        def call(context)
          key = context[:index_cfg][:key].to_s
          return EntryGuardPipeline::PASS unless key == 'BANKNIFTY'
          return EntryGuardPipeline::PASS if banknifty_last_week?(instrument: context[:instrument])

          { blocked: 'BANKNIFTY entry only in last week before monthly expiry' }
        end
      end
    end
  end
end
