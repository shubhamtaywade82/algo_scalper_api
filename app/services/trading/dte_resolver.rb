# frozen_string_literal: true

module Trading
  # Resolves days-to-expiry for an entry pick from derivative metadata or chain.
  class DteResolver
    class << self
      def days_to_expiry(pick:, index_cfg:)
        expiry = expiry_date_for(pick: pick, index_cfg: index_cfg)
        return nil unless expiry

        (expiry - Time.zone.today).to_i
      rescue StandardError => e
        Rails.logger.warn("[DteResolver] #{e.class} - #{e.message}")
        nil
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
        if pick[:derivative_id].present?
          return Derivative.find_by(id: pick[:derivative_id])
        end

        security_id = pick[:security_id].to_s
        return nil if security_id.empty?

        segment = pick[:segment] || pick['segment']
        Derivative.find_by(security_id: security_id, segment: segment.to_s)
      rescue StandardError
        nil
      end

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
