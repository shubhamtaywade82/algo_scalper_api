# frozen_string_literal: true

module AutoExp
  class Evaluator
    DRAW_LIMIT = 1.20

    def improved?(metrics, best)
      return true if best.nil?

      pf = metrics[:profit_factor] || 0.0
      dd = metrics[:drawdown] || 999.9

      # Improvement: Higher profit factor and DD within limit of best DD
      pf > best[:profit_factor] &&
        dd <= (best[:drawdown] * DRAW_LIMIT)
    end
  end
end
