# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TradingBot::SelfLearning do
  let(:config) { Ai::TradingBot::Config.new(mode: 'paper') }
  let(:self_learning) { described_class.new(config) }

  describe '#fetch_recent_closed_trades (private)' do
    it 'pulls real exited PositionTracker data instead of the old hardcoded []' do
      tracker = create(:position_tracker, :exited, :paper, entry_price: 100, exit_price: 120, last_pnl_rupees: 500)

      trades = self_learning.send(:fetch_recent_closed_trades)

      expect(trades).not_to be_empty
      row = trades.find { |t| t[:symbol] == tracker.symbol }
      expect(row).to include(entry_price: 100.0, exit_price: 120.0, pnl: 500.0)
    end

    it 'scopes to paper trades when config is in paper mode' do
      create(:position_tracker, :exited, :paper)
      create(:position_tracker, :exited, paper: false)

      trades = self_learning.send(:fetch_recent_closed_trades)

      expect(trades.size).to eq(PositionTracker.paper.exited.count)
    end

    it 'does not include active (non-exited) positions' do
      create(:position_tracker, status: 'active', paper: true)

      trades = self_learning.send(:fetch_recent_closed_trades)
      expect(trades).to be_empty
    end
  end
end
