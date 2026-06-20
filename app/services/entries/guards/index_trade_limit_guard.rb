# frozen_string_literal: true

module Entries
  module Guards
    # Enforces per-index trade_limits.max_trades_per_day from index config.
    class IndexTradeLimitGuard
      class << self
        include BaseGuard

        def call(context)
          index_cfg = context[:index_cfg]
          return PASS unless index_cfg

          max_trades = max_trades_per_day(index_cfg)
          return PASS if max_trades.nil?

          index_key = index_cfg[:key].to_s.upcase
          return paused_block(index_key) if max_trades.zero?

          trades_today = Live::DailyLimits.new.get_daily_trades(index_key)
          return PASS if trades_today < max_trades

          { blocked: "index trade limit #{index_key} (#{trades_today}/#{max_trades})" }
        rescue StandardError => e
          Rails.logger.warn("[IndexTradeLimitGuard] #{e.class} - #{e.message}")
          PASS
        end

        private

        def max_trades_per_day(index_cfg)
          index_cfg.dig(:trade_limits, :max_trades_per_day) ||
            index_cfg.dig('trade_limits', 'max_trades_per_day')
        end

        def paused_block(index_key)
          { blocked: "index paused #{index_key} (max_trades_per_day=0)" }
        end
      end
    end
  end
end
