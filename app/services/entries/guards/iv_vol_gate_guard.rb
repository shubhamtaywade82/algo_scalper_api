# frozen_string_literal: true

module Entries
  module Guards
    # Entry guard that gates entries based on the option's implied volatility (IV) rank.
    # It blocks entry if IV Rank is too high (risk of IV crush) or too low (lack of movement).
    class IvVolGateGuard
      include BaseGuard

      def self.call(context)
        return PASS unless enabled?

        pick = context[:pick]
        index_cfg = context[:index_cfg]
        index_key = index_cfg[:key].to_s.upcase

        # Get current IV from pick
        current_iv = pick[:iv] || pick['iv'] || pick[:implied_volatility] || pick['implied_volatility']
        return PASS unless current_iv&.to_f&.positive?

        current_iv = current_iv.to_f

        # Fetch 30 days of historical ATM IV snapshots for index
        historical_ivs = IvSnapshot.historical_iv(index_key: index_key.downcase, days: 30)

        # If not enough historical snapshots, pass to avoid locking
        return PASS if historical_ivs.size < 5

        all_ivs = (historical_ivs + [current_iv]).compact
        min_iv = all_ivs.min.to_f
        max_iv = all_ivs.max.to_f

        # Calculate IV Rank (0.0 to 1.0)
        iv_rank = (max_iv - min_iv).zero? ? 0.0 : (current_iv - min_iv) / (max_iv - min_iv)

        max_allowed = max_iv_rank
        min_allowed = min_iv_rank

        if iv_rank > max_allowed
          return { blocked: "Strike-specific IV Rank (#{(iv_rank * 100).round(1)}%) is too high (max allowed: #{(max_allowed * 100).round(1)}%)" }
        end

        if iv_rank < min_allowed
          return { blocked: "Strike-specific IV Rank (#{(iv_rank * 100).round(1)}%) is too low (min allowed: #{(min_allowed * 100).round(1)}%)" }
        end

        PASS
      rescue StandardError => e
        Rails.logger.warn("[IvVolGateGuard] Error: #{e.class} - #{e.message}")
        PASS
      end

      def self.enabled?
        cfg = AlgoConfig.fetch.dig(:risk, :iv_vol_gate) || {}
        cfg[:enabled] != false
      end

      def self.max_iv_rank
        cfg = AlgoConfig.fetch.dig(:risk, :iv_vol_gate) || {}
        (cfg[:max_iv_rank] || 0.50).to_f
      end

      def self.min_iv_rank
        cfg = AlgoConfig.fetch.dig(:risk, :iv_vol_gate) || {}
        (cfg[:min_iv_rank] || 0.10).to_f
      end
    end
  end
end
