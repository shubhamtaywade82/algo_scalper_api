# frozen_string_literal: true

# Routes orders to either Paper::Placer (paper trading) or Orders::Placer (live trading)
# based on PAPER_MODE environment variable:
#
# PAPER_MODE=true  -> paper trading (simulated orders)
# PAPER_MODE=false -> live trading (real orders via DhanHQ)
#
# Default behavior if PAPER_MODE is not set:
# - Checks PAPER_TRADING env var (backward compatibility)
# - Checks config/algo.yml paper_trading.enabled
# - Falls back to live trading if nothing is set
module Orders
  class Router
    class << self
      def buy_market!(**)
        target.buy_market!(**)
      end

      def sell_market!(**)
        target.sell_market!(**)
      end

      def exit_position!(**)
        target.exit_position!(**)
      end

      def target
        if paper_trading_enabled?
          Paper::Placer
        else
          Orders::Placer
        end
      end

      def paper_trading_enabled?
        # Check PAPER_MODE environment variable first
        mode = ENV.fetch('PAPER_MODE', nil)
        return false if %w[false 0].include?(mode)
        return true if %w[true 1].include?(mode)

        # Fallback to PAPER_TRADING for backward compatibility
        return true if ENV['PAPER_TRADING'] == 'true'

        # Check config file
        cfg_enabled = begin
          Rails.application.config_for(:algo).dig('paper_trading', 'enabled')
        rescue StandardError
          nil
        end
        cfg_enabled == true
      end
    end
  end
end
