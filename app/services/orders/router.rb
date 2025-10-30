# frozen_string_literal: true

# Routes orders to either Paper::Placer (paper trading) or Orders::Placer (live trading)
# based on PAPER_MODE environment variable:
#
# PAPER_MODE=true  -> paper trading (simulated orders)
# PAPER_MODE=false -> live trading (real orders via DhanHQ)
#
# Note: Mode selection is now standardized to ENV-only (ExecutionMode.paper?)
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
        # Standardized to use ExecutionMode (ENV-based only)
        ExecutionMode.paper?
      end
    end
  end
end
