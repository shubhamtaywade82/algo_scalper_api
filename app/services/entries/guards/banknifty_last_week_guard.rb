# frozen_string_literal: true

module Entries
  module Guards
    class BankniftyLastWeekGuard
      class << self
        def call(context)
          index_cfg = context[:index_cfg] || {}
          key = index_cfg[:key].to_s
          return EntryGuardPipeline::PASS unless key == 'BANKNIFTY'
          return EntryGuardPipeline::PASS unless only_last_week_enabled?(index_cfg)
          return EntryGuardPipeline::PASS if EntryGuard.banknifty_last_week?

          { blocked: 'BANKNIFTY entry only in last week before monthly expiry' }
        end

        private

        def only_last_week_enabled?(index_cfg)
          rules = index_cfg[:expiry_rules] || {}
          rules.fetch(:only_last_week, false) == true
        end
      end
    end
  end
end
