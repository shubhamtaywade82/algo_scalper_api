# frozen_string_literal: true

module Entries
  module Guards
    # Selling profits from IV richness (the opposite of IvVolGateGuard's buying
    # concern about IV crush) — only sell when IV rank is high enough that there's
    # real premium to harvest. Reuses IvVolGateGuard's historical IV rank data
    # access; the pass/block direction is inverted for selling.
    class SellingIvRankGuard
      include BaseGuard

      def self.call(context)
        return PASS unless context[:position_side].to_s == 'short'
        return PASS unless enabled?

        pick = context[:pick]
        index_key = context[:index_cfg][:key].to_s.downcase

        current_iv = pick[:iv] || pick['iv'] || pick[:implied_volatility] || pick['implied_volatility']
        return PASS unless current_iv&.to_f&.positive?

        historical_ivs = IvSnapshot.historical_iv(index_key: index_key, days: 30)
        return PASS if historical_ivs.size < 5

        iv_rank = rank_of(current_iv.to_f, historical_ivs)
        min_allowed = min_iv_rank

        if iv_rank < min_allowed
          { blocked: "IV rank (#{(iv_rank * 100).round(1)}%) too low to sell premium (min #{(min_allowed * 100).round(1)}%)" }
        else
          PASS
        end
      rescue StandardError => e
        Rails.logger.warn("[SellingIvRankGuard] Error: #{e.class} - #{e.message}")
        PASS
      end

      def self.rank_of(current_iv, historical_ivs)
        all_ivs = (historical_ivs + [current_iv]).compact
        min_iv = all_ivs.min.to_f
        max_iv = all_ivs.max.to_f
        (max_iv - min_iv).zero? ? 0.0 : (current_iv - min_iv) / (max_iv - min_iv)
      end

      def self.enabled?
        config[:enabled] != false
      end

      def self.min_iv_rank
        (config[:min_iv_rank] || 0.40).to_f
      end

      def self.config
        AlgoConfig.fetch.dig(:risk, :selling_iv_rank_gate) || {}
      end
    end
  end
end
