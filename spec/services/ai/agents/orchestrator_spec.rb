# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::Orchestrator do
  before do
    # DynamicConfigAgent is the only Level 2 agent and would otherwise make a
    # real Ollama call (and potentially write AlgoConfig) from this unrelated spec.
    allow(Services::Ai::OllamaClient.instance).to receive(:enabled?).and_return(false)
  end

  describe '#run_cycle' do
    it 'runs every agent exactly once per configured index_key and returns their results' do
      results = described_class.run_cycle(index_keys: %w[NIFTY BANKNIFTY])

      expect(results.keys).to include(
        :risk_management, :post_trade_analysis, :execution,
        :market_analysis_NIFTY, :strategy_selection_NIFTY, :calibration_NIFTY, :dynamic_config_NIFTY,
        :market_analysis_BANKNIFTY, :strategy_selection_BANKNIFTY, :calibration_BANKNIFTY, :dynamic_config_BANKNIFTY
      )
    end

    it 'never places, cancels, or modifies an order, and never mutates PositionTracker rows' do
      expect { described_class.run_cycle(index_keys: ['NIFTY']) }.not_to change(PositionTracker, :count)
      expect { described_class.run_cycle(index_keys: ['NIFTY']) }.not_to(change { PositionTracker.pluck(:updated_at) })
    end

    it 'logs advisor-level decisions for every agent except the Level 2 DynamicConfigAgent' do
      described_class.run_cycle(index_keys: ['NIFTY'])

      logs = AgentDecisionLog.where(created_at: 5.seconds.ago..)
      expect(logs).to be_present

      by_agent = logs.group_by(&:agent_name)
      expect(by_agent['dynamic_config_agent'].map(&:authority_level).uniq).to eq(['level_2'])
      (by_agent.keys - ['dynamic_config_agent']).each do |name|
        expect(by_agent[name].map(&:authority_level).uniq).to eq(['advisor'])
      end
    end

    it 'never writes AlgoConfig when Ollama is disabled' do
      expect { described_class.run_cycle(index_keys: ['NIFTY']) }.not_to change(AlgoConfigChangeLog, :count)
    end
  end
end
