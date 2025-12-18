# frozen_string_literal: true

require 'bigdecimal'
require 'redis'

module Capital
  # BalanceManager tracks running balance for paper trading
  # Updates balance on trade entry (reduces by trade cost) and exit (adds realized P&L)
  # For live trading, still uses API but tracks realized P&L separately
  class BalanceManager
    include Singleton

    # Redis key prefix for balance tracking
    BALANCE_KEY_PREFIX = 'capital:balance:paper'
    INITIAL_BALANCE_KEY = 'capital:balance:initial'

    def initialize
      @lock = Mutex.new
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    rescue StandardError => e
      Rails.logger.error("[BalanceManager] Redis init error: #{e.message}") if defined?(Rails)
      @redis = nil
    end

    # Get current available balance
    # For paper trading: Returns running balance (initial - deployed + realized P&L)
    # For live trading: Returns API balance + realized P&L
    # @return [BigDecimal] Available balance
    def available_balance
      return live_balance_with_realized_pnl if live_trading?

      paper_running_balance
    rescue StandardError => e
      Rails.logger.error("[BalanceManager] Failed to get available balance: #{e.class} - #{e.message}")
      fallback_balance
    end

    # Record trade entry - reduces available balance by trade cost
    # @param tracker [PositionTracker] Position tracker
    # @param entry_price [BigDecimal, Float] Entry price
    # @param quantity [Integer] Quantity
    def record_entry(tracker, entry_price:, quantity:)
      return unless paper_trading_enabled?

      trade_cost = BigDecimal(entry_price.to_s) * quantity.to_i
      reduce_balance(trade_cost, tracker: tracker, reason: 'entry')
      Rails.logger.info(
        "[BalanceManager] Entry recorded: #{tracker.order_no} " \
        "cost=₹#{trade_cost.round(2)} balance=₹#{paper_running_balance.round(2)}"
      )
    rescue StandardError => e
      Rails.logger.error("[BalanceManager] Failed to record entry: #{e.class} - #{e.message}")
    end

    # Record trade exit - adds realized capital back to balance
    # For options: Adds back entry cost + P&L (full exit proceeds)
    # This makes realized capital available for new trades on the same exchange
    # @param tracker [PositionTracker] Position tracker
    def record_exit(tracker)
      return unless paper_trading_enabled?

      # Calculate realized capital = entry cost + P&L
      entry_cost = calculate_entry_cost(tracker)
      realized_pnl = tracker.last_pnl_rupees || BigDecimal(0)
      realized_capital = entry_cost + BigDecimal(realized_pnl.to_s)

      add_balance(realized_capital, tracker: tracker, reason: 'exit')
      Rails.logger.info(
        "[BalanceManager] Exit recorded: #{tracker.order_no} " \
        "entry_cost=₹#{entry_cost.round(2)} pnl=₹#{realized_pnl.to_f.round(2)} " \
        "realized_capital=₹#{realized_capital.round(2)} balance=₹#{paper_running_balance.round(2)}"
      )
    rescue StandardError => e
      Rails.logger.error("[BalanceManager] Failed to record exit: #{e.class} - #{e.message}")
    end

    # Reset balance to initial value (for new sessions)
    # @param initial_balance [BigDecimal, Float, nil] Initial balance (uses config if nil)
    def reset_balance(initial_balance = nil)
      return unless paper_trading_enabled?

      balance = initial_balance || initial_paper_balance
      balance_value = BigDecimal(balance.to_s)

      return unless @redis

      @lock.synchronize do
        @redis.set(INITIAL_BALANCE_KEY, balance_value.to_s)
        @redis.set(paper_balance_key, balance_value.to_s)
        Rails.logger.info("[BalanceManager] Balance reset to ₹#{balance_value.round(2)}")
      end
    rescue StandardError => e
      Rails.logger.error("[BalanceManager] Failed to reset balance: #{e.class} - #{e.message}")
    end

    # Get initial balance (from config or Redis)
    # @return [BigDecimal] Initial balance
    def initial_balance
      return BigDecimal(0) unless paper_trading_enabled?
      return BigDecimal(initial_paper_balance.to_s) unless @redis

      cached = @redis.get(INITIAL_BALANCE_KEY)
      return BigDecimal(cached) if cached

      balance = initial_paper_balance
      @redis.set(INITIAL_BALANCE_KEY, balance.to_s)
      BigDecimal(balance.to_s)
    rescue StandardError => e
      Rails.logger.error("[BalanceManager] Failed to get initial balance: #{e.class} - #{e.message}")
      BigDecimal(initial_paper_balance.to_s)
    end

    # Get total realized P&L from all exited positions
    # @return [BigDecimal] Total realized P&L
    def total_realized_pnl
      return BigDecimal(0) unless paper_trading_enabled?

      PositionTracker.exited_paper.sum do |tracker|
        tracker.last_pnl_rupees || BigDecimal(0)
      end
    rescue StandardError => e
      Rails.logger.error("[BalanceManager] Failed to calculate realized P&L: #{e.class} - #{e.message}")
      BigDecimal(0)
    end

    # Get total deployed capital (sum of all active positions)
    # @return [BigDecimal] Total deployed capital
    def total_deployed_capital
      return BigDecimal(0) unless paper_trading_enabled?

      PositionTracker.paper.active.sum do |tracker|
        next BigDecimal(0) unless tracker.entry_price && tracker.quantity

        BigDecimal(tracker.entry_price.to_s) * tracker.quantity.to_i
      end
    rescue StandardError => e
      Rails.logger.error("[BalanceManager] Failed to calculate deployed capital: #{e.class} - #{e.message}")
      BigDecimal(0)
    end

    private

    # Get paper trading running balance
    # Running balance = Initial balance - Deployed capital + Realized P&L
    # @return [BigDecimal] Running balance
    def paper_running_balance
      return BigDecimal(initial_paper_balance.to_s) unless @redis

      @lock.synchronize do
        cached = @redis.get(paper_balance_key)
        if cached
          BigDecimal(cached)
        else
          # Initialize from config if not cached
          balance = initial_paper_balance
          @redis.set(paper_balance_key, balance.to_s)
          @redis.set(INITIAL_BALANCE_KEY, balance.to_s)
          BigDecimal(balance.to_s)
        end
      end
    end

    # Reduce balance by amount (on entry)
    # @param amount [BigDecimal] Amount to reduce
    # @param tracker [PositionTracker] Position tracker
    # @param reason [String] Reason for reduction
    def reduce_balance(amount, tracker:, reason:)
      return unless @redis

      @lock.synchronize do
        current = paper_running_balance
        new_balance = [current - amount, BigDecimal(0)].max
        @redis.set(paper_balance_key, new_balance.to_s)
        Rails.logger.debug(
          "[BalanceManager] Balance reduced: #{reason} #{tracker.order_no} " \
          "amount=₹#{amount.round(2)} from=₹#{current.round(2)} to=₹#{new_balance.round(2)}"
        )
      end
    end

    # Add balance by amount (on exit)
    # @param amount [BigDecimal] Amount to add
    # @param tracker [PositionTracker] Position tracker
    # @param reason [String] Reason for addition
    def add_balance(amount, tracker:, reason:)
      return unless @redis

      @lock.synchronize do
        current = paper_running_balance
        new_balance = current + amount
        @redis.set(paper_balance_key, new_balance.to_s)
        Rails.logger.debug(
          "[BalanceManager] Balance added: #{reason} #{tracker.order_no} " \
          "amount=₹#{amount.round(2)} from=₹#{current.round(2)} to=₹#{new_balance.round(2)}"
        )
      end
    end

    # Get live balance with realized P&L added
    # For live trading, we still use API balance but add realized P&L from paper positions
    # This allows tracking realized P&L even in live mode
    # @return [BigDecimal] Live balance + realized P&L
    def live_balance_with_realized_pnl
      api_balance = Allocator.fetch_live_trading_balance
      realized_pnl = total_realized_pnl
      api_balance + realized_pnl
    end

    # Get initial paper balance from config
    # @return [BigDecimal] Initial balance
    def initial_paper_balance
      balance = AlgoConfig.fetch.dig(:paper_trading, :balance) || 100_000
      BigDecimal(balance.to_s)
    end

    # Get Redis key for paper balance
    # @return [String] Redis key
    def paper_balance_key
      "#{BALANCE_KEY_PREFIX}:#{Date.current.strftime('%Y%m%d')}"
    end

    # Check if paper trading is enabled
    # @return [Boolean]
    def paper_trading_enabled?
      Allocator.paper_trading_enabled?
    end

    # Check if live trading is enabled
    # @return [Boolean]
    def live_trading?
      !paper_trading_enabled?
    end

    # Calculate entry cost for a tracker
    # @param tracker [PositionTracker] Position tracker
    # @return [BigDecimal] Entry cost (entry_price × quantity)
    def calculate_entry_cost(tracker)
      return BigDecimal(0) unless tracker.entry_price && tracker.quantity

      BigDecimal(tracker.entry_price.to_s) * tracker.quantity.to_i
    end

    # Fallback balance if all else fails
    # @return [BigDecimal]
    def fallback_balance
      if paper_trading_enabled?
        initial_paper_balance
      else
        Allocator.fetch_live_trading_balance rescue BigDecimal(100_000)
      end
    end
  end
end
