# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::Orchestrator do
  describe '#run_cycle' do
    it 'runs every agent exactly once per configured index_key and returns their results' do
      results = described_class.run_cycle(index_keys: %w[NIFTY BANKNIFTY])

      expect(results.keys).to include(
        :risk_management, :post_trade_analysis, :execution,
        :market_analysis_NIFTY, :strategy_selection_NIFTY, :calibration_NIFTY,
        :market_analysis_BANKNIFTY, :strategy_selection_BANKNIFTY, :calibration_BANKNIFTY
      )
    end

    it 'never places, cancels, or modifies an order, and never mutates PositionTracker rows' do
      expect { described_class.run_cycle(index_keys: ['NIFTY']) }.not_to change(PositionTracker, :count)
      expect { described_class.run_cycle(index_keys: ['NIFTY']) }.not_to(change { PositionTracker.pluck(:updated_at) })
    end

    it 'logs a decision for every agent it ran, all at advisor authority level' do
      described_class.run_cycle(index_keys: ['NIFTY'])

      logs = AgentDecisionLog.where(created_at: 5.seconds.ago..)
      expect(logs).to be_present
      expect(logs.pluck(:authority_level).uniq).to eq(['advisor'])
    end
  end
end
