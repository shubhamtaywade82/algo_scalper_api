# frozen_string_literal: true

# Administrative conveniences for manual trading interventions.
# Provides thin wrappers around model-level helpers so ops teams
# can reuse the live trading pipeline without bypassing risk guards.
module Trading
  module AdminActions
    class << self
      # Buy a chosen option contract and start tracking immediately.
      #
      # Sizing policy (made explicit — error-handling review 2026-09):
      # an omitted qty deliberately requests allocator sizing via auto_size.
      # A malformed qty raises Errors::InvalidQuantity instead of quietly
      # becoming a 1-lot order.
      #
      # @param derivative_id [Integer] Instrument id of the traded contract
      #   (legacy Derivative ids still resolve via the consolidated mirror).
      # @param qty [Integer, nil] explicit quantity; nil = default sizing
      # @param product_type [String]
      # @param index_key [String, nil]
      # @param meta [Hash]
      # @return [Object, nil]
      # @raise [Errors::InvalidQuantity, Errors::ConfigurationError]
      def buy_derivative!(derivative_id:, qty: nil, product_type: "NORMAL", index_key: nil, meta: {})
        instrument = resolve_tradable(derivative_id)
        instrument.buy_option!(
          qty: qty,
          auto_size: qty.blank?,
          product_type: product_type,
          index_cfg: find_index_config(instrument: instrument, override_key: index_key),
          meta: meta
        )
      end

      # Sell (exit) an option contract position tracked by the system.
      #
      # Exit policy (made explicit — error-handling review 2026-09):
      #   * qty given ....... partial/explicit sell (strictly validated)
      #   * qty omitted ..... close the WHOLE tracked position — now the
      #     explicit close_position! command instead of an inferred liquidation
      #
      # @param derivative_id [Integer] Instrument id of the traded contract
      # @param qty [Integer, nil]
      # @param meta [Hash]
      # @return [Object, nil]
      # @raise [Errors::InvalidQuantity]
      def sell_derivative!(derivative_id:, qty: nil, meta: {})
        instrument = resolve_tradable(derivative_id)
        if qty.present?
          instrument.sell_option!(qty: qty, meta: meta)
        else
          instrument.close_position!(meta: meta)
        end
      end

      private

      def resolve_tradable(id)
        Instruments::LegacyResolver.by_legacy_id(id, require_derivative: true) ||
          raise(ActiveRecord::RecordNotFound, "No tradable instrument with id #{id}")
      end

      def find_index_config(instrument:, override_key: nil)
        key = (override_key || instrument.underlying_symbol || instrument.symbol_name).to_s
        return nil if key.blank?

        indices = IndexConfigLoader.load_indices
        indices.find { |cfg| cfg[:key].to_s.casecmp?(key) }
      end
    end
  end
end
