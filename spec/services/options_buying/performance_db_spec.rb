# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::PerformanceDb do
  let(:strategy_name) { 'orb_breakout' }
  let(:index_key) { 'NIFTY' }

  describe '.stats_for' do
    context 'when there are insufficient exited trades (less than 10)' do
      before do
        # Create only 5 exited trades
        5.times do |i|
          create_exited_tracker(strategy_name, index_key, last_pnl: 100.0 * i)
        end
      end

      it 'returns nil' do
        stats = described_class.stats_for(strategy_name, index_key)
        expect(stats).to be_nil
      end
    end

    context 'when there are enough exited trades (10 or more)' do
      before do
        # Create 6 winning trades (last_pnl = +200) and 4 losing trades (last_pnl = -100)
        # Total = 10 trades, Win Rate = 60%, Avg Win = 200, Avg Loss = 100, Payout Ratio = 2.0
        6.times do
          create_exited_tracker(strategy_name, index_key, last_pnl: 200.0)
        end
        4.times do
          create_exited_tracker(strategy_name, index_key, last_pnl: -100.0)
        end
      end

      it 'calculates stats correctly' do
        stats = described_class.stats_for(strategy_name, index_key)
        expect(stats).not_to be_nil
        expect(stats[:win_rate]).to eq(0.6)
        expect(stats[:payout_ratio]).to eq(2.0)
        expect(stats[:sample_size]).to eq(10)
        expect(stats[:avg_win]).to eq(200.0)
        expect(stats[:avg_loss]).to eq(100.0)
      end
    end
  end

  def create_exited_tracker(strategy, index, last_pnl:)
    # Find or create a mock instrument
    instrument = Instrument.find_by(security_id: '26000') || create(:instrument, security_id: '26000', segment: 'derivatives')

    PositionTracker.create!(
      order_no: SecureRandom.uuid,
      security_id: '26000',
      segment: 'NSE_FNO',
      status: :exited,
      entry_strategy: strategy,
      index_key: index,
      last_pnl_rupees: last_pnl,
      avg_price: 100.0,
      quantity: 50,
      instrument: instrument,
      watchable: instrument,
      exited_at: Time.current
    )
  end
end
