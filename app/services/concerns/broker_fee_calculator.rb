# frozen_string_literal: true

# Broker fee calculation helper
# Handles broker fees for order execution (₹20 per order, ₹40 per trade)
module BrokerFeeCalculator
  class << self
    # Calculate total broker fees for a complete trade (entry + exit)
    # Returns: BigDecimal fee amount
    def fee_per_trade
      fee_per_order = BigDecimal((broker_fee_config[:fee_per_order] || 20).to_s)
      fee_per_order * 2 # Entry + Exit
    end

    # Calculate broker fee for a single order execution
    # Returns: BigDecimal fee amount
    def fee_per_order
      BigDecimal((broker_fee_config[:fee_per_order] || 20).to_s)
    end

    # Calculate net PnL after deducting broker fees
    # Params:
    #   gross_pnl: BigDecimal - Gross PnL before fees
    #   is_exited: Boolean - Whether the position is exited (full trade fees) or active (entry fee only)
    # Returns: BigDecimal net PnL
    def net_pnl(gross_pnl, is_exited: false)
      return gross_pnl if gross_pnl.nil?

      gross_pnl_bd = BigDecimal(gross_pnl.to_s)
      fees = is_exited ? fee_per_trade : fee_per_order
      gross_pnl_bd - fees
    end

    # Calculate gross PnL from net PnL (reverse of net_pnl)
    # Used for exit rule checks on active positions
    # Params:
    #   net_pnl: BigDecimal - Net PnL after fees
    #   is_exited: Boolean - Whether the position is exited (full trade fees) or active (entry fee only)
    # Returns: BigDecimal gross PnL
    def gross_pnl(net_pnl, is_exited: false)
      return net_pnl if net_pnl.nil?

      net_pnl_bd = BigDecimal(net_pnl.to_s)
      fees = is_exited ? fee_per_trade : fee_per_order
      net_pnl_bd + fees
    end

    # Check if broker fees are enabled
    def enabled?
      broker_fee_config[:enabled] != false
    end

    private

    def broker_fee_config
      AlgoConfig.fetch[:broker_fees] || {}
    rescue StandardError
      {}
    end
  end
end
