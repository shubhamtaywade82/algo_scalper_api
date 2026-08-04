# frozen_string_literal: true

module AutoExp
  class Evaluator
    # Max drawdown increase allowed (1.20 = 20% increase)
    DRAW_LIMIT = 1.20

    def improved?(metrics, best)
      return true if best.nil?

      pf = metrics[:profit_factor]
      dd = metrics[:drawdown]

      # Strategy: Better profit factor while keeping drawdown within limit
      # If drawdown is 0, we use a small epsilon to avoid division by zero
      current_best_dd = [best[:drawdown], 0.0001].max

      pf > best[:profit_factor] &&
        dd <= current_best_dd * DRAW_LIMIT
    end
  end
end
