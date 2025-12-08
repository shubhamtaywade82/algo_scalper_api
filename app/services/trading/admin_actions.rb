# frozen_string_literal: true

# Administrative conveniences for manual trading interventions.
# Provides thin wrappers around model-level helpers so ops teams
# can reuse the live trading pipeline without bypassing risk guards.
module Trading
  module AdminActions
    class << self
      # Buy a chosen derivative (CE/PE) and start tracking immediately.
      # @param derivative_id [Integer]
      # @param qty [Integer, nil]
      # @param product_type [String]
      # @param index_key [String, nil]
      # @param meta [Hash]
      # @return [Object, nil]
      def buy_derivative!(derivative_id:, qty: nil, product_type: 'INTRADAY', index_key: nil, meta: {})
        derivative = Derivative.find(derivative_id)
        derivative.buy_option!(
          qty: qty,
          product_type: product_type,
          index_cfg: find_index_config(derivative: derivative, override_key: index_key),
          meta: meta
        )
      end

      # Sell (exit) a derivative position tracked by the system.
      # @param derivative_id [Integer]
      # @param qty [Integer, nil]
      # @param meta [Hash]
      # @return [Object, nil]
      def sell_derivative!(derivative_id:, qty: nil, meta: {})
        Derivative.find(derivative_id).sell_option!(qty: qty, meta: meta)
      end

      private

      def find_index_config(derivative:, override_key: nil)
        key = (override_key || derivative.underlying_symbol || derivative.symbol_name).to_s
        return nil if key.blank?

        indices = IndexConfigLoader.load_indices
        indices.find { |cfg| cfg[:key].to_s.casecmp?(key) }
      rescue StandardError => e
        # Rails.logger.error("[AdminActions] Failed to resolve index config for #{key}: #{e.message}")
        nil
      end
    end
  end
end

