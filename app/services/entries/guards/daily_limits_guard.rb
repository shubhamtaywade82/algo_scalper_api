# frozen_string_literal: true

module Entries
  module Guards
    class DailyLimitsGuard
      class << self
        def call(context)
          return EntryGuardPipeline::PASS if daily_limits_allow_entry?(index_cfg: context[:index_cfg])

          { blocked: "daily loss/profit limits for #{context[:index_cfg][:key]}" }
        end

        private

        def daily_limits_allow_entry?(index_cfg:)
          return true unless daily_limits_enabled?

          daily_limits = Live::DailyLimits.new
          result = daily_limits.can_trade?(index_key: index_cfg[:key])

          symbol = index_cfg[:key].to_s.upcase
          if %w[NIFTY SENSEX BANKNIFTY].include?(symbol)
            trades_today = daily_limits.get_daily_trades(symbol)
            return false if trades_today >= 3
          end

          return true if result[:allowed]

          # Only block on loss/profit limits, NOT trade frequency limits
          case result[:reason]
          when 'trade_frequency_limit_exceeded', 'global_trade_frequency_limit_exceeded'
            true
          else
            false
          end
        end

        def daily_limits_enabled?
          AlgoConfig.fetch.dig(:risk, :daily_limits, :enabled) == true
        rescue StandardError
          false
        end
      end
    end
  end
end
