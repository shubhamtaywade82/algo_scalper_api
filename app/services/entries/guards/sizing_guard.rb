# frozen_string_literal: true

module Entries
  module Guards
    class SizingGuard
      include BaseGuard

      def self.call(context)
        new(context).call
      end

      def initialize(context)
        @context = context
        @index_cfg = context[:index_cfg]
        @pick = context[:pick]
        @direction = context[:direction]
        @ltp = context[:ltp]
        @entry_metadata = context[:entry_metadata]
        @permission = context[:permission]
        @scale_multiplier = context[:scale_multiplier]
      end

      def call
        symbol = @index_cfg[:key].to_s.upcase
        permission_sym = (@permission || @entry_metadata&.dig(:permission) || :scale_ready).to_sym
        
        profile = Trading::InstrumentExecutionProfile.for(symbol)
        return { blocked: 'execution_only_blocked_by_profile' } if execution_only_blocked?(profile, permission_sym)

        lot_size = Trading::LotCalculator.lot_size_for(symbol)
        permission_cap = profile[:max_lots_by_permission][permission_sym].to_i

        cap_lots = Trading::CapitalAllocator.max_lots(
          premium: @ltp.to_f,
          lot_size: lot_size,
          permission_cap: permission_cap
        )
        return { blocked: 'capital_sizing_cap_zero' } if cap_lots <= 0

        quantity_by_allocator = Capital::Allocator.qty_for(
          index_cfg: @index_cfg,
          entry_price: @ltp.to_f,
          derivative_lot_size: lot_size,
          scale_multiplier: @scale_multiplier
        )

        quantity_by_cap = cap_lots * lot_size
        quantity = [quantity_by_allocator.to_i, quantity_by_cap.to_i].min
        quantity = (quantity / lot_size) * lot_size # ensure lot-aligned

        if quantity < lot_size
          return { blocked: 'quantity_below_lot_minimum' }
        end

        @context[:quantity] = quantity
        @context[:lot_size] = lot_size
        PASS
      end

      private

      def execution_only_blocked?(profile, permission_sym)
        permission_sym == :execution_only && profile[:allow_execution_only] == false
      end
    end
  end
end
