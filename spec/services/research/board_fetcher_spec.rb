# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::BoardFetcher do
  describe '.call' do
    before do
      allow(Research::OptionCandleFetcher).to receive(:call) do |option_type:, strike_label:, **|
        "#{option_type}:#{strike_label}"
      end
    end

    it 'fetches every strike from ATM-max_distance to ATM+max_distance for both CE and PE' do
      board = described_class.call(
        symbol: 'NIFTY', spot: 24_982, expiry_flag: 'WEEK',
        from_date: '2026-07-10', to_date: '2026-07-11', max_distance: 2
      )

      expect(board.keys).to contain_exactly('CE', 'PE')
      expect(board['CE'].keys).to contain_exactly('ATM-2', 'ATM-1', 'ATM', 'ATM+1', 'ATM+2')
      expect(board['CE']['ATM']).to eq('CE:ATM')
      expect(board['PE']['ATM+1']).to eq('PE:ATM+1')
      expect(Research::OptionCandleFetcher).to have_received(:call).exactly(10).times
    end
  end
end
