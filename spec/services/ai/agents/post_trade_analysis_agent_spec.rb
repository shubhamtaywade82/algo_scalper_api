# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::PostTradeAnalysisAgent do
  subject(:agent) { described_class.new }

  describe '#run' do
    it 'creates a TradeMemory for an exited tracker that does not have one yet' do
      tracker = create(:position_tracker, :exited, entry_price: 100, exit_price: 120,
                                                   entry_strategy: 'orb_breakout', last_pnl_rupees: 500)
      create(:trade_analytic, position_tracker: tracker, entry_price: 100, exit_price: 120,
                              max_favorable_excursion: 25, max_adverse_excursion: -5, strategy: 'orb_breakout')

      expect { agent.run }.to change(TradeMemory, :count).by(1)
    end

    it 'populates the created TradeMemory from real tracker/analytic data' do
      tracker = create(:position_tracker, :exited, entry_price: 100, exit_price: 120,
                                                   entry_strategy: 'orb_breakout', last_pnl_rupees: 500)
      create(:trade_analytic, position_tracker: tracker, entry_price: 100, exit_price: 120,
                              max_favorable_excursion: 25, max_adverse_excursion: -5, strategy: 'orb_breakout')

      agent.run
      memory = TradeMemory.find_by(position_tracker: tracker)

      expect(memory.symbol).to eq(tracker.symbol)
      expect(memory.strategy_name).to eq('orb_breakout')
      expect(memory.pnl_rupees).to eq(tracker.last_pnl_rupees)
    end

    it 'is idempotent — does not create a second TradeMemory for the same tracker' do
      tracker = create(:position_tracker, :exited)
      create(:trade_analytic, position_tracker: tracker)
      create(:trade_memory, position_tracker: tracker)

      expect { agent.run }.not_to change(TradeMemory, :count)
    end

    it 'skips active (non-exited) positions' do
      create(:position_tracker, status: 'active')

      expect { agent.run }.not_to change(TradeMemory, :count)
    end

    it 'logs a decision with the processed count' do
      tracker = create(:position_tracker, :exited)
      create(:trade_analytic, position_tracker: tracker)

      result = agent.run
      expect(result[:output][:processed]).to eq(1)
      expect(AgentDecisionLog.for_agent('post_trade_analysis_agent').count).to eq(1)
    end

    it 'continues processing other trackers if one fails' do
      good = create(:position_tracker, :exited)
      create(:trade_analytic, position_tracker: good)
      bad = create(:position_tracker, :exited)
      create(:trade_analytic, position_tracker: bad, entry_price: 0) # forces div-by-zero guard path

      expect { agent.run }.to change(TradeMemory, :count).by(2)
    end
  end
end
