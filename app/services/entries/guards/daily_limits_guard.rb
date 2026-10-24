# frozen_string_literal: true

module Entries
  module Guards
    class DailyLimitsGuard
      class << self
        def call(context)
          return EntryGuardPipeline::PASS if daily_limits_allow_entry?(context)

          { blocked: "daily loss/profit limits for #{context[:index_cfg][:key]}" }
        end

        private

        def daily_limits_allow_entry?(context)
          return true unless daily_limits_enabled?

          index_cfg = context[:index_cfg]
          strategy_slug = context[:strategy_slug]

          daily_limits = Live::DailyLimits.new

          # Per-strategy frequency check
          if strategy_slug.present?
            max_strategy = strategy_limits_config.dig(strategy_slug.to_sym, :max_trades_per_day) ||
                           strategy_limits_config.dig(strategy_slug, 'max_trades_per_day')
            if max_strategy
              current = daily_limits.get_strategy_daily_trades(strategy_slug)
              return false if current >= max_strategy.to_i
            end
          end

          result = daily_limits.can_trade?(index_key: index_cfg[:key])

          symbol = index_cfg[:key].to_s.upcase
          if %w[NIFTY SENSEX BANKNIFTY].include?(symbol)
            trades_today = daily_limits.get_daily_trades(symbol)
            return false if trades_today >= 3
          end

          return true if result[:allowed]

          # Only block on loss/profit limits, NOT trade frequency limits
          case result[:reason]
          when 'trade_frequency_limit_exceeded', 'global_trade_frequency_limit_exceeded',
               'strategy_trade_frequency_limit_exceeded'
            true
          else
            false
          end
        end

        def daily_limits_enabled?
          config = AlgoConfig.fetch
          config.dig(:daily_limits, :enabled) == true ||
            config.dig(:risk, :daily_limits, :enabled) == true
        rescue StandardError
          false
        end

        def strategy_limits_config
          AlgoConfig.fetch[:strategy_limits] || {}
        rescue StandardError
          {}
        end
      end
    end
  end
end
