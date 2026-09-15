# frozen_string_literal: true

module Trading
  # Resolves days-to-expiry for an entry pick from derivative metadata or chain.
  #
  # Contract (error-handling review wave 4):
  #   * nil = "expiry genuinely unknown" (no expiry on the pick, no derivative
  #     row, no chain data, or an unparseable date string) — a documented
  #     domain outcome; callers apply their default DTE tier.
  #   * Errors propagate — the previous blanket `rescue StandardError -> nil`
  #     also swallowed config/DB failures into "unknown", degrading DTE tiering
  #     exactly when the system is misconfigured. The entry guards have their
  #     own fail-closed handlers for Errors::Error.
  class DteResolver
    class << self
      def days_to_expiry(pick:, index_cfg:)
        expiry = expiry_date_for(pick: pick, index_cfg: index_cfg)
        return nil unless expiry

        (expiry - Time.zone.today).to_i
      end

      private

      def expiry_date_for(pick:, index_cfg:)
        raw = pick[:expiry_date] || pick['expiry_date']
        return coerce_date(raw) if raw.present?

        derivative = derivative_for(pick)
        return derivative.expiry_date if derivative&.expiry_date

        nearest = Options::DerivativeChainAnalyzer.new(index_key: index_cfg[:key]).nearest_expiry
        coerce_date(nearest)
      end

      def derivative_for(pick)
        Instruments::LegacyResolver.resolve_pick(pick)
      end

      # Malformed date strings (e.g. "not-a-date") parse to nil — the
      # documented "expiry unknown" outcome, not a swallowed error.
      def coerce_date(raw)
        case raw
        when Date then raw
        when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
        when String then Date.parse(raw)
        end
      rescue ArgumentError
        nil
      end
    end
  end
end
