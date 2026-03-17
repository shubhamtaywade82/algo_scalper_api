# frozen_string_literal: true

module Live
  module UnderlyingLtpResolver
    def resolve_underlying_ltp(index_key)
      return nil unless index_key

      cfg = AlgoConfig.fetch[:indices]&.find { |i| i[:key].to_s == index_key.to_s }
      return nil unless cfg

      Live::TickQuery.for_security(segment: cfg[:segment], security_id: cfg[:sid])&.ltp
    rescue StandardError
      nil
    end
  end
end
