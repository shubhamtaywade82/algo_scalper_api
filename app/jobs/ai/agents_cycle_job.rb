# frozen_string_literal: true

module Ai
  # Runs the multi-agent AI cycle (MarketAnalysis, RiskManagement, StrategySelection, Calibration)
  # across all active trading indices during market hours.
  class AgentsCycleJob < ApplicationJob
    queue_as :background

    def perform(index_keys: nil)
      keys = index_keys.presence || IndexConfigLoader.load_indices.map { |c| c[:key].to_s.upcase }
      Rails.logger.info("[Ai::AgentsCycleJob] Executing AI cycle for #{keys.join(', ')}")

      results = Ai::Agents::Orchestrator.run_cycle(index_keys: keys)
      Rails.logger.info("[Ai::AgentsCycleJob] Completed AI cycle with #{results.keys.size} agent outputs")
      results
    rescue StandardError => e
      Rails.logger.error("[Ai::AgentsCycleJob] Execution failed: #{e.class} - #{e.message}")
    end
  end
end
