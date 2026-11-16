# frozen_string_literal: true

class GetExperimentHistoryTool < ApplicationMCPTool
  tool_name 'get_experiment_history'
  description 'Recent auto-experiment (AutoExp) results: commit, profit factor, drawdown, win rate, status. Read-only.'

  property :limit, type: 'integer', description: 'Max rows (default 10, max 50)'

  def perform
    rows = AutoExp::ResultsStore.load_recent((limit || 10).to_i.clamp(1, 50))
    render_json(count: rows.size, experiments: rows)
  end
end
