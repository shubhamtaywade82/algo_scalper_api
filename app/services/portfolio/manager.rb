module Portfolio
  class Manager
    MAX_CAPITAL = 100_000.0
    MAX_RISK_PER_STRATEGY = 0.02
    MAX_TOTAL_RISK = 0.05

    def initialize(strategies:)
      @strategies = strategies
    end

    def allocate(contexts)
      allocations = {}
      total_risk = 0

      contexts.each do |strategy_name, context|
        next unless context.tradable?

        risk = compute_risk(context)
        next if total_risk + risk > MAX_TOTAL_RISK

        allocations[strategy_name] = {
          capital: MAX_CAPITAL * risk,
          risk: risk
        }

        total_risk += risk
      end

      allocations
    end

    private

    def compute_risk(context)
      base = MAX_RISK_PER_STRATEGY

      if context.score >= 80
        base * 1.5
      elsif context.score >= 60
        base
      else
        base * 0.5
      end
    end
  end
end
