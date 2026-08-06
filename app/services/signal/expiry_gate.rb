# frozen_string_literal: true

module Signal
  # Resolves the nearest option expiry for an index and whether trading is
  # allowed against it (expiry-day session rules). Extracted from Signal::Engine.
  class ExpiryGate
    class << self
      def resolve_nearest_expiry_date(index_cfg:, no_trade_gate: nil)
        exp = no_trade_gate&.dig(:expiry_date)
        return exp if exp.present?

        Options::DerivativeChainAnalyzer.new(index_key: index_cfg[:key]).nearest_expiry
      rescue StandardError => e
        Rails.logger.warn("[Signal] resolve_nearest_expiry_date #{index_cfg[:key]}: #{e.class} — #{e.message}")
        nil
      end

      def expiry_trade_allowed?(symbol)
        return true if AlgoConfig.run_mode == 'exit_testing'

        expiry_model = "Strategies::ExpiryModel".safe_constantize
        return true unless expiry_model

        expiry_model.trade_allowed?(symbol: symbol)
      rescue StandardError => e
        Rails.logger.error("[Signal] ExpiryModel unavailable (#{e.class}: #{e.message}); allowing trade")
        true
      end
    end
  end
end
