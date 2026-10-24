# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradeMemory do
  it 'requires a lesson and a unique position_tracker' do
    tracker = create(:position_tracker, :exited)
    create(:trade_memory, position_tracker: tracker)

    duplicate = build(:trade_memory, position_tracker: tracker)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors.attribute_names).to include(:position_tracker_id)
  end

  describe '#winner? / #loser?' do
    it 'classifies by pnl_rupees sign' do
      winner = build(:trade_memory, pnl_rupees: 500)
      loser = build(:trade_memory, pnl_rupees: -500)

      expect(winner).to be_winner
      expect(loser).to be_loser
    end
  end

  describe 'scopes' do
    it 'filters by symbol, strategy, and category' do
      tracker = create(:position_tracker, :exited)
      memory = create(:trade_memory, position_tracker: tracker, symbol: 'NIFTY',
                                     strategy_name: 'orb_breakout', category: 'exit_execution')

      expect(described_class.for_symbol('nifty')).to include(memory)
      expect(described_class.for_strategy('orb_breakout')).to include(memory)
      expect(described_class.by_category('exit_execution')).to include(memory)
    end
  end
end
