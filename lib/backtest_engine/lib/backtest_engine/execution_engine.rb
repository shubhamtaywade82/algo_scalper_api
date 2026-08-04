module BacktestEngine
  class ExecutionEngine
    DEFAULT_SLIPPAGE_PCT = 0.02

    def initialize(lot_size:, quantity: 1, slippage_pct: DEFAULT_SLIPPAGE_PCT)
      @lot_size = lot_size
      @quantity = quantity
      @slippage_pct = slippage_pct
    end

    def entry_fill(raw_price)
      apply_slippage(raw_price, :buy)
    end

    def exit_fill(raw_price)
      apply_slippage(raw_price, :sell)
    end

    def pnl(entry_price, exit_price)
      (exit_price - entry_price) * contract_size
    end

    def capital_required(entry_price)
      entry_price * contract_size
    end

    private

    attr_reader :lot_size, :quantity, :slippage_pct

    def contract_size
      lot_size * quantity
    end

    def apply_slippage(price, side)
      return 0.0 unless price

      factor = side == :buy ? 1 + slippage_pct : 1 - slippage_pct
      (price * factor).to_f
    end
  end
end

