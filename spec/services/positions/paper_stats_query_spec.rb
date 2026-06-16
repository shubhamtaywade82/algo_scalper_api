# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::PaperStatsQuery do
  describe '.call' do
    let(:active_tracker) { create_active_tracker }
    let(:cache) { instance_double(Live::RedisPnlCache) }

    before do
      create_exited_tracker(BigDecimal('100'))
      create_exited_tracker(BigDecimal('-20'))
      active_tracker
      allow(cache).to receive(:fetch_pnl).with(active_tracker.id).and_return({ pnl: '10', pnl_pct: '0.01' })
      allow(cache).to receive(:fetch_pnl).and_return(nil)
      allow(Live::RedisPnlCache).to receive(:instance).and_return(cache)
      allow(Capital::Allocator).to receive(:paper_trading_balance).and_return(1000)
      allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(false)
      allow(Portfolio::PaperPeakTracker).to receive(:observe!)
      allow(Portfolio::PaperPeakTracker).to receive(:current_for).and_return(0.0)
    end

    it 'returns aggregated paper stats hash' do
      result = described_class.call(paper: true)

      expect(result[:total_trades]).to eq(2)
      expect(result[:winners]).to eq(1)
      expect(result[:losers]).to eq(1)
      expect(result[:stats_scope]).to eq('paper')
      expect(Portfolio::PaperPeakTracker).to have_received(:observe!).with(anything, paper: true)
    end

    it 'falls back to all exits when auto scope is empty but day has live trades' do
      PositionTracker.delete_all
      allow(AlgoConfig).to receive(:paper_trading_enabled?).and_return(true)
      create(:position_tracker, :exited, paper: false, segment: 'NSE_FNO',
                                         exited_at: Time.current, last_pnl_rupees: BigDecimal('-500'))

      result = described_class.call

      expect(result[:total_trades]).to eq(1)
      expect(result[:realized_pnl_rupees]).to eq(-500.0)
      expect(result[:stats_scope]).to eq('all')
    end

    context 'when effective mode is live' do
      before do
        allow(AlgoConfig).to receive(:paper_trading_enabled?).and_return(false)
      end

      it 'aggregates live exited positions only' do
        create(:position_tracker, :exited, paper: false, segment: 'NSE_FNO',
                                           exited_at: Time.current, last_pnl_rupees: BigDecimal('-500'))
        create(:position_tracker, :paper, :exited, segment: 'NSE_FNO',
                                                  exited_at: Time.current, last_pnl_rupees: BigDecimal('999'))

        result = described_class.call(paper: false)

        expect(result[:total_trades]).to eq(1)
        expect(result[:realized_pnl_rupees]).to eq(-500.0)
        expect(result[:stats_scope]).to eq('live')
      end
    end

    def create_exited_tracker(pnl)
      create(:position_tracker, :paper, :exited, segment: 'NSE_FNO', exited_at: Time.current, last_pnl_rupees: pnl)
    end

    def create_active_tracker
      create(:position_tracker, :paper, status: 'active', segment: 'NSE_FNO', last_pnl_rupees: BigDecimal('0'))
    end
  end
end
