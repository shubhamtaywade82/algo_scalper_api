# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentsCycleJob do
  describe '#perform' do
    it 'invokes Ai::Agents::Orchestrator.run_cycle with provided indices' do
      allow(Ai::Agents::Orchestrator).to receive(:run_cycle)
        .with(index_keys: %w[NIFTY BANKNIFTY])
        .and_return({ market_analysis_NIFTY: { confidence: 0.8 } })

      described_class.perform_now(index_keys: %w[NIFTY BANKNIFTY])

      expect(Ai::Agents::Orchestrator).to have_received(:run_cycle)
        .with(index_keys: %w[NIFTY BANKNIFTY])
    end
  end
end
