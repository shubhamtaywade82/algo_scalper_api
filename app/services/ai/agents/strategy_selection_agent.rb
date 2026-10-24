# frozen_string_literal: true

module Ai
  module Agents
    # Blueprint §8.4 "Strategy Selection Agent" — ranks strategies by
    # realized expectancy from TradeMemory instead of the fixed
    # regime-to-strategy mapping in OptionsBuying::StrategyEngine.
    #
    # Level 1 (Advisor) only: this ranking is a recommendation logged to
    # AgentDecisionLog. It does not touch the live strategy-selection
    # mapping — see the report's Phase 3 for what a bounded override would
    # look like; that is future work, not something this class does.
    class StrategySelectionAgent < BaseAgent
      MIN_TRADES_PER_STRATEGY = 5

      private

      def perform(index_key: nil, min_trades: MIN_TRADES_PER_STRATEGY)
        scope = TradeMemory.where.not(strategy_name: [nil, ''])
        scope = scope.for_symbol(index_key) if index_key.present?

        ranked = rank_strategies(scope.to_a, min_trades)

        {
          decision_type: 'strategy_ranking',
          confidence: ranked.empty? ? 0.0 : [ranked.size / 5.0, 1.0].min.round(4),
          output: {
            index_key: index_key&.to_s&.upcase,
            ranked_strategies: ranked,
            recommended_strategy: ranked.first&.fetch(:strategy)
          }
        }
      end

      def rank_strategies(trades, min_trades)
        ranked = trades.group_by(&:strategy_name).filter_map do |name, group|
          next if group.size < min_trades

          wins = group.count(&:winner?)
          total_pnl = group.sum { |t| t.pnl_rupees.to_f }

          {
            strategy: name,
            trades: group.size,
            win_rate: (wins.to_f / group.size).round(4),
            avg_pnl_rupees: (total_pnl / group.size).round(2),
            total_pnl_rupees: total_pnl.round(2)
          }
        end

        ranked.sort_by { |s| -s[:avg_pnl_rupees] }
      end
    end
  end
end
