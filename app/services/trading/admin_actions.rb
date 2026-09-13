# frozen_string_literal: true

# Administrative conveniences for manual trading interventions.
# Provides thin wrappers around model-level helpers so ops teams
# can reuse the live trading pipeline without bypassing risk guards.
module Trading
  module AdminActions
    class << self
      # Buy a chosen option contract and start tracking immediately.
      # @param derivative_id [Integer] Instrument id of the traded contract
      #   (legacy Derivative ids still resolve via the consolidated mirror).
      # @param qty [Integer, nil]
      # @param product_type [String]
      # @param index_key [String, nil]
      # @param meta [Hash]
      # @return [Object, nil]
      def buy_derivative!(derivative_id:, qty: nil, product_type: "NORMAL", index_key: nil, meta: {})
        instrument = resolve_tradable(derivative_id)
        instrument.buy_option!(
          qty: qty,
          product_type: product_type,
          index_cfg: find_index_config(instrument: instrument, override_key: index_key),
          meta: meta
        )
      end

      # Sell (exit) an option contract position tracked by the system.
      # @param derivative_id [Integer] Instrument id of the traded contract
      # @param qty [Integer, nil]
      # @param meta [Hash]
      # @return [Object, nil]
      def sell_derivative!(derivative_id:, qty: nil, meta: {})
        resolve_tradable(derivative_id).sell_option!(qty: qty, meta: meta)
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
      rescue StandardError
        # Rails.logger.error("[AdminActions] Failed to resolve index config for #{key}: #{e.message}")
        nil
      end
    end
  end
end
