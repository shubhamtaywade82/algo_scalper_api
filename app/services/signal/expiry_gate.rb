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

      # Entries are only taken on indices whose nearest expiry is within signals.max_expiry_days
      # (default 7): beyond that the contract is a far-dated monthly with wide spreads and
      # premiums above the band, which the scheduler already skips. Unknown expiry is not blocked
      # (same as the scheduler: a data problem must not silently stop all trading).
      #
      # @return [Boolean] true when the nearest expiry is more than max_expiry_days away
      def beyond_entry_window?(index_cfg)
        expiry = resolve_nearest_expiry_date(index_cfg: index_cfg)
        return false if expiry.blank?

        (expiry.to_date - Time.zone.today).to_i > max_expiry_days
      end

      def max_expiry_days
        (AlgoConfig.fetch.dig(:signals, :max_expiry_days) || 7).to_i
      rescue StandardError
        7
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
