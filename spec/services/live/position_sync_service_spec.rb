# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::PositionSyncService do
  let(:service) { described_class.instance }
  let(:active_cache) { instance_double(Positions::ActivePositionsCache) }
  let(:hub) { instance_double(Live::MarketFeedHub) }

  before do
    # Reset internal state
    service.instance_variable_set(:@last_sync, nil)
    service.instance_variable_set(:@last_dhan_count, nil)
    service.instance_variable_set(:@last_tracked_count, nil)
    service.instance_variable_set(:@last_paper_count, nil)
    
    # Mock singletons
    allow(Positions::ActivePositionsCache).to receive(:instance).and_return(active_cache)
    allow(Live::MarketFeedHub).to receive(:instance).and_return(hub)
    allow(TradingSession::Service).to receive(:market_open?).and_return(true)
    
    # Mock hub basic behavior to avoid "unexpected message" errors during registration/subscription/unsubscription
    allow(hub).to receive(:running?).and_return(true)
    allow(hub).to receive(:connected?).and_return(true)
    allow(hub).to receive(:start!).and_return(true)
    allow(hub).to receive(:subscribed?).and_return(false)
    allow(hub).to receive(:subscribe).and_return({ already_subscribed: false })
    allow(hub).to receive(:unsubscribe).and_return(true)
    
    # Mock AlgoConfig for paper trading state
    allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: false } })
    service.instance_variable_set(:@paper_mode, false)
    
    # Mock Redis caches that are called during mark_exited!
    allow(Live::RedisPnlCache.instance).to receive(:clear_tracker)
    allow(Live::RedisTickCache.instance).to receive(:clear_tick)
    allow(Live::TickCache).to receive(:delete)
  end

  describe 'singleton' do
    it 'returns the same instance' do
      expect(described_class.instance).to eq(described_class.instance)
    end
  end

  describe '#sync_positions!' do
    context 'when market is closed' do
      before { allow(TradingSession::Service).to receive(:market_open?).and_return(false) }

      it 'does not perform sync' do
        expect(DhanHQ::Models::Position).not_to receive(:active)
        service.sync_positions!
      end
    end

    context 'when in live trading mode' do
      let(:dhan_position) do
        double('DhanHQ::Models::Position',
          security_id: '12345',
          trading_symbol: 'NIFTY24MAR25000CE',
          exchange_segment: 'NSE_FNO',
          net_qty: 50,
          buy_avg: 150.0,
          to_h: { 'security_id' => '12345' }
        )
      end

      before do
        allow(DhanHQ::Models::Position).to receive(:active).and_return([dhan_position])
        allow(active_cache).to receive(:active_trackers).and_return([])
        allow(PositionTracker).to receive(:clear_orphaned_redis_pnl!)
      end

      it 'calls sync_live_positions and clears orphaned redis pnl' do
        expect(PositionTracker).to receive(:clear_orphaned_redis_pnl!)
        service.sync_positions!
      end

      context 'when untracked positions are found' do
        let!(:instrument) { create(:instrument, security_id: '12345', exchange: :nse, segment: :derivatives) }
        let!(:derivative) { create(:derivative, instrument: instrument, security_id: '12345', exchange: :nse, segment: :derivatives) }

        it 'creates a new PositionTracker' do
          expect {
            service.sync_positions!
          }.to change(PositionTracker, :count).by(1)

          tracker = PositionTracker.last
          expect(tracker.security_id).to eq('12345')
          expect(tracker.status).to eq('active')
          expect(tracker.meta['synced_from_dhan']).to be true
        end
      end

      context 'when orphaned trackers are found' do
        let!(:tracker) { create(:position_tracker, :long_position, security_id: '99999', status: 'active', segment: 'NSE_FNO') }

        before do
          allow(active_cache).to receive(:active_trackers).and_return([tracker])
        end

        it 'marks them as exited with position_sync_orphaned reason' do
          service.sync_positions!
          tracker.reload
          expect(tracker.status).to eq('exited')
          expect(tracker.meta['exit_reason']).to eq('position_sync_orphaned')
        end
      end
    end

    context 'when in paper trading mode' do
      let!(:paper_tracker) { create(:position_tracker, :long_position, :paper, status: 'active', segment: 'NSE_FNO') }

      before do
        service.instance_variable_set(:@paper_mode, true)
        allow(active_cache).to receive(:active_trackers).and_return([paper_tracker])
        allow(PositionTracker).to receive(:clear_orphaned_redis_pnl!)
      end

      it 'ensures paper positions are subscribed in the feed hub' do
        expect(hub).to receive(:subscribed?).with(hash_including(security_id: paper_tracker.security_id)).and_return(false)
        expect(Positions::FeedSubscription).to receive(:call).with(hash_including(tracker: paper_tracker)).and_call_original
        expect(hub).to receive(:subscribe).with(hash_including(security_id: paper_tracker.security_id))
        
        service.sync_positions!
      end
    end
  end

  describe '#force_sync!' do
    let(:now) { Time.current }

    before do
      allow(service).to receive(:market_open?).and_return(true)
      allow(service).to receive(:sync_live_positions)
      # Control time via Time.current mock
      allow(Time).to receive(:current).and_return(now)
      allow(Time).to receive(:now).and_return(now)
    end

    it 'bypasses the interval check' do
      service.instance_variable_set(:@last_sync, now - 10.seconds)
      
      # Should not sync normally because of 30s interval
      service.sync_positions!
      expect(service).not_to have_received(:sync_live_positions)
      
      # Should sync when forced
      service.force_sync!
      expect(service).to have_received(:sync_live_positions)
    end
  end
end
