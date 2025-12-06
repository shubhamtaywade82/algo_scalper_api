# frozen_string_literal: true

module Risk
  # Profit Halt Service: Prevents trading after achieving significant realized profits
  # When realized PnL exceeds threshold (default: 20% of capital), only allows
  # high-probability trades (confidence >= 60%) to protect profits
  class ProfitHaltService
    # Default threshold: 20% of initial capital
    DEFAULT_HALT_THRESHOLD_PCT = 20.0

    # Default minimum confidence when halted: 60% (0.6)
    DEFAULT_MIN_CONFIDENCE_WHEN_HALTED = 0.6

    class << self
      # Check if trading should be halted based on realized PnL
      # @return [Hash] { halted: Boolean, realized_pnl_pct: Float, reason: String }
      def check_halt_status
        realized_pnl_pct = calculate_realized_pnl_pct
        halt_threshold = halt_threshold_pct

        if realized_pnl_pct >= halt_threshold
          {
            halted: true,
            realized_pnl_pct: realized_pnl_pct.round(2),
            threshold_pct: halt_threshold,
            reason: "Realized PnL (#{realized_pnl_pct.round(2)}%) exceeds halt threshold (#{halt_threshold}%)",
            min_confidence_required: min_confidence_when_halted
          }
        else
          {
            halted: false,
            realized_pnl_pct: realized_pnl_pct.round(2),
            threshold_pct: halt_threshold,
            reason: nil,
            min_confidence_required: nil
          }
        end
      rescue StandardError => e
        Rails.logger.error("[ProfitHaltService] Error checking halt status: #{e.class} - #{e.message}")
        # Fail open: allow trading if check fails
        {
          halted: false,
          realized_pnl_pct: 0.0,
          threshold_pct: halt_threshold_pct,
          reason: "Error calculating halt status: #{e.message}",
          min_confidence_required: nil
        }
      end

      # Check if a trade should be allowed given current halt status and signal confidence
      # @param confidence_score [Float, nil] Signal confidence score (0.0 to 1.0). If nil, assumes low confidence when halted.
      # @return [Hash] { allowed: Boolean, reason: String }
      def can_trade?(confidence_score: nil)
        halt_status = check_halt_status

        # If not halted, allow all trades
        return { allowed: true, reason: nil } unless halt_status[:halted]

        # If halted, only allow high-probability trades
        min_confidence = halt_status[:min_confidence_required] || DEFAULT_MIN_CONFIDENCE_WHEN_HALTED
        
        # If confidence_score is nil, assume low confidence and block
        if confidence_score.nil?
          return {
            allowed: false,
            reason: "Trading halted: Realized PnL #{halt_status[:realized_pnl_pct]}% >= #{halt_status[:threshold_pct]}%. " \
                    "Signal confidence not provided (required: #{(min_confidence * 100).round(1)}%)"
          }
        end

        confidence = confidence_score.to_f

        if confidence >= min_confidence
          {
            allowed: true,
            reason: "High-probability trade allowed (confidence: #{(confidence * 100).round(1)}% >= #{min_confidence * 100}%)"
          }
        else
          {
            allowed: false,
            reason: "Trading halted: Realized PnL #{halt_status[:realized_pnl_pct]}% >= #{halt_status[:threshold_pct]}%. " \
                    "Signal confidence #{(confidence * 100).round(1)}% < required #{(min_confidence * 100).round(1)}%"
          }
        end
      rescue StandardError => e
        Rails.logger.error("[ProfitHaltService] Error checking trade permission: #{e.class} - #{e.message}")
        # Fail open: allow trading if check fails
        { allowed: true, reason: "Error checking halt status: #{e.message}" }
      end

      private

      # Calculate realized PnL as percentage of initial capital
      # @return [Float] Realized PnL percentage
      def calculate_realized_pnl_pct
        if Capital::Allocator.paper_trading_enabled?
          calculate_paper_realized_pnl_pct
        else
          calculate_live_realized_pnl_pct
        end
      end

      # Calculate realized PnL for paper trading
      # @return [Float] Realized PnL percentage
      def calculate_paper_realized_pnl_pct
        stats = PositionTracker.paper_trading_stats_with_pct
        stats[:realized_pnl_pct] || 0.0
      end

      # Calculate realized PnL for live trading
      # Uses initial capital from config or current balance as fallback
      # @return [Float] Realized PnL percentage
      def calculate_live_realized_pnl_pct
        # Get exited positions with realized PnL
        exited_positions = PositionTracker.where(status: :exited).where.not(paper: true)
        realized_pnl_rupees = exited_positions.sum { |t| t.last_pnl_rupees.to_f }

        # Get initial capital (from config or use current balance as proxy)
        initial_capital = initial_capital_for_live_trading

        return 0.0 if initial_capital.zero?

        (realized_pnl_rupees / initial_capital * 100.0).round(2)
      end

      # Get initial capital for live trading
      # Tries to get from config, falls back to current balance
      # @return [BigDecimal] Initial capital amount
      def initial_capital_for_live_trading
        # Try to get from config first
        config_capital = AlgoConfig.fetch.dig(:capital, :initial_amount)
        return BigDecimal(config_capital.to_s) if config_capital.present? && config_capital.to_f.positive?

        # Fallback to current balance (less accurate but better than zero)
        current_balance = Capital::Allocator.available_cash
        return current_balance if current_balance.positive?

        # Last resort: use paper trading balance as estimate
        Capital::Allocator.paper_trading_balance
      end

      # Get halt threshold percentage from config
      # @return [Float] Halt threshold percentage
      def halt_threshold_pct
        threshold = AlgoConfig.fetch.dig(:risk, :profit_halt_threshold_pct)
        threshold = threshold.to_f if threshold.present?
        threshold.positive? ? threshold : DEFAULT_HALT_THRESHOLD_PCT
      end

      # Get minimum confidence required when halted
      # @return [Float] Minimum confidence (0.0 to 1.0)
      def min_confidence_when_halted
        confidence = AlgoConfig.fetch.dig(:risk, :profit_halt_min_confidence)
        confidence = confidence.to_f if confidence.present?
        confidence.positive? && confidence <= 1.0 ? confidence : DEFAULT_MIN_CONFIDENCE_WHEN_HALTED
      end
    end
  end
end
