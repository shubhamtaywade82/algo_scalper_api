# frozen_string_literal: true

module Entries
  module Guards
    class RiskPolicyGuard
      include BaseGuard

      def self.call(context)
        new(context).call
      end

      def initialize(context)
        @context = context
        @index_cfg = context[:index_cfg]
        @pick = context[:pick]
        @quantity = context[:quantity]
        @ltp = context[:ltp]
        @lot_size = context[:lot_size]
      end

      def call
        risk_policy = Policies::RiskPolicy.new(
          index_key: @index_cfg[:key].to_s,
          proposed_qty: @quantity,
          entry_price: @ltp.to_f,
          lot_size: @lot_size
        )

        if risk_policy.permitted?
          PASS
        else
          { blocked: risk_policy.reasons.join('; ') }
        end
      end
    end
  end
end
