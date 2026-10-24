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
        ltp_f = @ltp.to_f
        unless ltp_f.finite? && ltp_f.positive?
          return { blocked: "invalid_entry_ltp for #{@index_cfg[:key]}: #{@ltp.inspect}" }
        end

        # Error-handling review 2026-09 (wave 2): a missing permission used to
        # silently size as :scale_ready (15 lots on NIFTY). Permission must be
        # explicit — unknown deployment authorization blocks the entry.
        permission_sym = resolve_permission
        return { blocked: 'permission_unresolved — sizing requires an explicit permission level' } if permission_sym.nil?

        symbol = @index_cfg[:key].to_s.upcase
        profile = Trading::InstrumentExecutionProfile.for(symbol)
        return { blocked: 'execution_only_blocked_by_profile' } if execution_only_blocked?(profile, permission_sym)

        lot_size = Trading::LotCalculator.lot_size_for(symbol)
        permission_cap = permission_cap_for(profile, permission_sym)

        if permission_cap.zero?
          # Legitimate configured zero (e.g. SENSEX execution_only) — distinct
          # from capital exhaustion so operators can tell them apart.
          return { blocked: "permission_cap_zero for #{symbol} #{permission_sym}" }
        end

        cap_lots = Trading::CapitalAllocator.max_lots(
          premium: ltp_f,
          lot_size: lot_size,
          permission_cap: permission_cap
        )
        return { blocked: 'capital_sizing_cap_zero' } if cap_lots <= 0

        quantity_by_allocator = Capital::Allocator.qty_for(
          index_cfg: @index_cfg,
          entry_price: ltp_f,
          derivative_lot_size: lot_size,
          scale_multiplier: @scale_multiplier
        )

        # Allocator output is a trading decision: unresolvable garbage blocks
        # with its own reason instead of masquerading as "quantity 0".
        allocator_qty = Orders::Quantity.resolve(quantity_by_allocator)
        if allocator_qty.nil?
          return { blocked: "allocator_quantity_invalid for #{symbol}: #{quantity_by_allocator.inspect}" }
        end

        quantity_by_cap = cap_lots * lot_size
        quantity = [allocator_qty, quantity_by_cap].min
        quantity = (quantity / lot_size) * lot_size # ensure lot-aligned

        if quantity < lot_size
          return { blocked: 'quantity_below_lot_minimum' }
        end

        @context[:quantity] = quantity
        @context[:lot_size] = lot_size
        PASS
      end

      private

      # @return [Symbol, nil] explicit permission level; nil when neither the
      #   context nor the entry metadata states one
      def resolve_permission
        raw = @permission || @entry_metadata&.dig(:permission)
        raw.present? ? raw.to_sym : nil
      end

      # @raise [Errors::InvariantViolation] when the profile constant is missing
      #   the permission tier or carries a non-Integer cap — the profile table
      #   is frozen source code, so this is corruption, not a runtime condition
      def permission_cap_for(profile, permission_sym)
        raw = profile[:max_lots_by_permission][permission_sym]
        unless raw.is_a?(Integer)
          raise Errors::InvariantViolation,
                "InstrumentExecutionProfile max_lots_by_permission[#{permission_sym}] must be an Integer — got #{raw.inspect}"
        end

        raw
      end

      def execution_only_blocked?(profile, permission_sym)
        permission_sym == :execution_only && profile[:allow_execution_only] == false
      end
    end
  end
end
