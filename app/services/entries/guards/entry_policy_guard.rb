# frozen_string_literal: true

module Entries
  module Guards
    class EntryPolicyGuard
      include BaseGuard

      def self.call(context)
        entry_policy = Policies::EntryPolicy.new(
          index_cfg: context[:index_cfg],
          direction: context[:direction]
        )

        if entry_policy.permitted?
          PASS
        else
          { blocked: entry_policy.reasons.join('; ') }
        end
      end
    end
  end
end
