# frozen_string_literal: true

module Orders
  # Computes real NSE F&O charges for a single order leg (one side of one trade),
  # replacing the flat ₹40/trade placeholder previously hardcoded in ReportsController.
  # Rates per docs/AlgoScalperPlatform-v2.0.md PR-012. Pure function — no I/O, no state.
  class ChargesCalculator
    BROKERAGE_PER_ORDER = BigDecimal('20.0')
    STT_SELL_PCT = BigDecimal('0.000125')      # 0.0125% on sell-side turnover, options only
    EXCHANGE_TXN_PCT = BigDecimal('0.00053')   # ~0.053% on turnover
    GST_PCT = BigDecimal('0.18')               # on brokerage + exchange transaction charges
    STAMP_DUTY_BUY_PCT = BigDecimal('0.00003') # 0.003% on buy-side turnover
    SEBI_TURNOVER_PCT = BigDecimal('0.000001') # ₹10 per crore of turnover

    # @param side [String, Symbol] "buy" or "sell"
    # @param quantity [Integer]
    # @param price [BigDecimal, Float, Numeric]
    # @param segment [String, nil] unused for now — rate table doesn't vary by segment yet
    # @return [BigDecimal] total charges for this leg, rounded to paise
    def self.call(side:, quantity:, price:, segment: nil)
      new(side: side, quantity: quantity, price: price, segment: segment).call
    end

    def initialize(side:, quantity:, price:, segment: nil)
      @side = side.to_s.downcase
      @turnover = BigDecimal(price.to_s) * quantity.to_i
      @segment = segment
    end

    def call
      exchange_txn = (@turnover * EXCHANGE_TXN_PCT).round(4)
      gst = ((BROKERAGE_PER_ORDER + exchange_txn) * GST_PCT).round(4)

      (BROKERAGE_PER_ORDER + stt + exchange_txn + gst + stamp_duty + sebi_turnover_fee).round(4)
    end

    private

    def stt
      return BigDecimal('0') unless sell_side?

      (@turnover * STT_SELL_PCT).round(4)
    end

    def stamp_duty
      return BigDecimal('0') unless buy_side?

      (@turnover * STAMP_DUTY_BUY_PCT).round(4)
    end

    def sebi_turnover_fee
      (@turnover * SEBI_TURNOVER_PCT).round(4)
    end

    def sell_side?
      @side == 'sell'
    end

    def buy_side?
      @side == 'buy'
    end
  end
end
