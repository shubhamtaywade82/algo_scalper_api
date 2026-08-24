# frozen_string_literal: true

module Ai
  module Agents
    # Blueprint §8.9 "Orchestrator" — runs one advisory pass across all six
    # agents and returns their results. This is deliberately NOT wired into
    # lib/trading_system/supervisor.rb (the live 11-service trading daemon):
    # adding a 12th always-on thread to that process is a real architectural
    # change the report scopes at Phase 3+, not something to fold in here.
    # Invoke this on demand (rake ai:agents:run_cycle, a console, or a
    # recurring job you deliberately opt into) instead.
    #
    # It has no authority to override any agent's output or act on their
    # behalf — see AgentSupervisor for the capability model this respects.
    class Orchestrator
      DEFAULT_INDEX_KEYS = %w[NIFTY BANKNIFTY SENSEX].freeze

      def self.run_cycle(index_keys: DEFAULT_INDEX_KEYS)
        new.run_cycle(index_keys: index_keys)
      end

      def run_cycle(index_keys: DEFAULT_INDEX_KEYS)
        results = {
          risk_management: RiskManagementAgent.new.run,
          post_trade_analysis: PostTradeAnalysisAgent.new.run,
          execution: ExecutionAgent.new.run
        }

        index_keys.each do |index_key|
          results[:"market_analysis_#{index_key}"] = MarketAnalysisAgent.new.run(index_key: index_key)
          results[:"strategy_selection_#{index_key}"] = StrategySelectionAgent.new.run(index_key: index_key)
          results[:"calibration_#{index_key}"] = CalibrationAgent.new.run(symbol: index_key)
        end

        results
      end
    end
  end
end
