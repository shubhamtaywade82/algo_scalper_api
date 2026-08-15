# frozen_string_literal: true

module Risk
  # Calculate margin for buying + selling + hedged strategies
  # Uses DhanHQ margin calculator API via your existing gem
  #
  class MarginEngine
    def self.check!(signal:, available_margin:)
      new(signal: signal, available_margin: available_margin).check!
    end

    def initialize(signal:, available_margin:)
      @signal = signal
      @available_margin = available_margin
    end

    def check!
      if single_leg_buying?
        check_buying_margin
      else
        check_api_margin
      end
    end

    private

    def single_leg_buying?
      @signal.legs.size == 1 && @signal.legs.first[:position_side] == 'long'
    end

    def check_buying_margin
      leg = @signal.legs.first
      margin = leg[:entry_price].to_f * leg[:quantity].to_i
      margin *= 1.05  # 5% buffer

      if margin > @available_margin
        { allowed: false, margin_required: margin, reason: "Buying margin ₹#{margin.round} > available ₹#{@available_margin.round}" }
      else
        { allowed: true, margin_required: margin }
      end
    end

    def check_api_margin
      # Use DhanHQ margin API for selling/hedged
      orders = @signal.legs.map do |leg|
        {
          security_id: leg[:security_id].to_s,
          exchange_segment: leg[:segment],
          transaction_type: leg[:position_side] == 'long' ? 'BUY' : 'SELL',
          quantity: leg[:quantity],
          product_type: 'INTRADAY',
          price: leg[:entry_price].to_f,
          order_type: 'LIMIT',
        }
      end

      begin
        # Call DhanHQ margin calculator via your gem
        dhan = Dhanhq::Client.instance
        result = dhan.calculate_margin(orders)

        total_margin = result['totalMargin'].to_f
        buffer = total_margin * 0.10  # 10% buffer for selling
        total_margin += buffer

        usage_limit = AlgoConfig.fetch.dig(:risk, :margin_usage_limit_pct) || 50
        max_allowed = @available_margin * (usage_limit / 100.0)

        if total_margin > max_allowed
          { allowed: false, margin_required: total_margin, reason: "Margin ₹#{total_margin.round} > limit ₹#{max_allowed.round}" }
        else
          { allowed: true, margin_required: total_margin }
        end

      rescue StandardError => e
        Rails.logger.error("[MarginEngine] API failed: #{e.message}")
        { allowed: false, margin_required: 0, reason: "Margin API failed" }
      end
    end
  end
end
