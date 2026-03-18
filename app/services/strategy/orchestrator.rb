module Strategy
  class Orchestrator
    def initialize(strategies:, portfolio_manager:)
      @strategies = strategies
      @portfolio_manager = portfolio_manager
    end

    def call(market:, indicators:)
      contexts = {}

      @strategies.each do |name, strategy|
        context = Context::Builder.call(
          market: market,
          indicators: indicators,
          regime_state: strategy[:regime_state]
        )

        contexts[name] = context
      end

      allocations = @portfolio_manager.allocate(contexts)

      execute(allocations, contexts, market, indicators)
    end

    private

    def execute(allocations, contexts, market, indicators)
      allocations.each do |name, alloc|
        strategy = @strategies[name][:instance]
        context = contexts[name]

        decision = strategy.call(
          context: context,
          market: market,
          indicators: indicators
        )

        place_order(decision, alloc) if decision
      end
    end

    def place_order(decision, allocation)
      # Integrate with your existing order system
      Orders::Executor.call(
        decision.merge(capital: allocation[:capital])
      )
    end
  end
end
