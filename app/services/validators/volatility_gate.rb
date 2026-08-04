# frozen_string_literal: true

module Validators
  class VolatilityGate
    IV_PERCENTILE_THRESHOLD = 0.50

    def initialize(underlying)
      @underlying = underlying
    end

    def check
      iv = current_iv
      return { pass: false, percentile: nil, reason: "No IV data available" } unless iv&.positive?

      iv_rank = Options::IvRankTracker.instance.percentile_rank(
        index_key: @underlying, iv: iv
      )
      return { pass: false, percentile: nil, reason: "IV history not yet seeded" } if iv_rank.nil?

      { pass: iv_rank < IV_PERCENTILE_THRESHOLD, percentile: (iv_rank * 100).round(1) }
    end

    private

    def current_iv
      snapshot = IvSnapshot.for_index(@underlying)
                           .where(snapshot_date: Time.zone.today)
                           .order(:created_at)
                           .last
      snapshot&.implied_volatility&.to_f
    end
  end
end
