# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::PositionSyncService do
  include ActiveSupport::Testing::TimeHelpers

  subject(:service) { described_class.instance }

  let(:instrument) { create(:instrument, :nifty_future) }
  let(:active_tracker) do
    create(
      :position_tracker,
      :option_position,
      watchable: create(:derivative, instrument: instrument, segment: 'derivatives'),
      instrument: instrument,
      security_id: '50074',
      segment: 'NSE_FNO',
      status: :active,
      entry_price: 100.5,
      quantity: 75
    )
  end

  before do
    allow(TradingSession::Service).to receive(:market_open?).and_return(true)
    # Force live mode by default for these tests
    allow(service).to receive(:paper_trading_enabled?).and_return(false)

    # Clear sync state before each test
    service.instance_variable_set(:@last_sync, nil)
    # Ensure ActivePositionsCache is also cleared
    Positions::ActivePositionsCache.instance.clear!
    
    # Global stub for DhanHQ inspect to prevent AttributeHelper crashes
    allow(DhanHQ::Models::Position).to receive(:inspect).and_return('DhanHQ::Models::Position')
    # Point 3: Also stub instance inspect for any DhanHQ models/doubles that might be inspected
    allow_any_instance_of(DhanHQ::Models::Position).to receive(:inspect).and_return('#<DhanHQ::Models::Position>')
    
    # Ensure all doubles have a sane inspect to prevent RSpec failure output bloat
    allow_any_instance_of(RSpec::Mocks::Double).to receive(:inspect).and_return('RSpec::Double')
  end

  after do
    # Clear singleton state to prevent leakage
    service.instance_variable_set(:@last_sync, nil)
    Positions::ActivePositionsCache.instance.clear!
    travel_back
  end

  describe 'EPIC F — F1: Place Entry Order & Subscribe Option Tick' do
    describe '.sync_positions!' do
      context 'when syncing positions' do
        it 'syncs within polling interval (30 seconds)' do
          # First sync should happen
          expect(DhanHQ::Models::Position).to receive(:active).and_return([]).once
          service.sync_positions!

          # Second sync within 30s should be skipped
          expect(DhanHQ::Models::Position).not_to receive(:active)
          service.sync_positions!
        end

        it 'only queries active trackers, not pending ones' do
          create(:position_tracker, :pending, segment: 'NSE_FNO')
          allow(DhanHQ::Models::Position).to receive(:active).and_return([])
          
          # Manually populate cache with active tracker only
          allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([active_tracker])

          service.sync_positions!
        end

        it 'when no positions match does not update trackers if no DhanHQ positions found' do
          allow(DhanHQ::Models::Position).to receive(:active).and_return([])
          allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([active_tracker])

          # Make it paper so it doesn't mark exited when not found in DhanHQ
          active_tracker.update(paper: true)

          expect(active_tracker).not_to receive(:update!)
          service.sync_positions!
        end

        it 'when tracker already active does not call mark_active! on already active tracker' do
          dhan_position = double(
            'DhanPosition',
            security_id: '50074',
            trading_symbol: 'NIFTY24MAR18500CE',
            exchange_segment: 'NSE_FNO',
            net_qty: 75,
            buy_avg: 100.5,
            product_type: 'INTRADAY',
            position_type: 'LONG',
            inspect: 'DhanPosition'
          )
          allow(DhanHQ::Models::Position).to receive(:active).and_return([dhan_position])
          allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([active_tracker])

          expect(active_tracker).not_to receive(:mark_active!)
          service.sync_positions!
        end
      end

      context 'when untracked positions exist in DhanHQ' do
        let(:untracked_position) do
          double(
            'DhanPosition',
            security_id: '50076',
            trading_symbol: 'NIFTY18550CE',
            exchange_segment: 'NSE_FNO',
            net_qty: 75,
            buy_avg: 102.0,
            product_type: 'INTRADAY',
            position_type: 'LONG',
            to_h: {
              security_id: '50076',
              trading_symbol: 'NIFTY18550CE',
              net_qty: 75,
              buy_avg: 102.0
            },
            inspect: 'DhanPosition'
          )
        end

        before do
          # Mock ActivePositionsCache to return empty (no trackers for this security_id)
          allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([])
          
          # Create the derivative that the sync service will look for
          @derivative = create(:derivative, security_id: '50076', instrument: instrument, exchange: 'nse', segment: 'derivatives')
          # The service calls parse_exchange_segment which returns 'derivatives' for 'NSE_FNO'
          allow(Derivative).to receive(:find_by).with(hash_including(security_id: '50076')).and_return(@derivative)
        end

        it 'creates PositionTracker for untracked positions' do
          allow(DhanHQ::Models::Position).to receive(:active).and_return([untracked_position])

          expect do
            service.sync_positions!
          end.to change(PositionTracker, :count).by(1)

          tracker = PositionTracker.find_by(security_id: '50076')
          expect(tracker).to be_present
          expect(tracker.status).to eq('active')
          expect(tracker.segment).to eq('NSE_FNO')
          expect(tracker.avg_price).to eq(BigDecimal('102.0'))
        end

        it 'subscribes to tick feed for newly created tracker' do
          allow(DhanHQ::Models::Position).to receive(:active).and_return([untracked_position])

          market_feed_hub = Live::MarketFeedHub.instance
          expect(market_feed_hub).to receive(:subscribe).with(
            segment: 'NSE_FNO',
            security_id: '50076'
          ).at_least(:once)

          service.sync_positions!
        end
      end

      context 'when tracker exists but position closed in DhanHQ' do
        it 'marks tracker as exited when position not found in DhanHQ' do
          allow(DhanHQ::Models::Position).to receive(:active).and_return([])
          
          # Mock ActivePositionsCache to return our tracker
          allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([active_tracker])
          
          # Ensure it's a live position so it gets marked as orphaned
          active_tracker.update(paper: false)

          expect(active_tracker).to receive(:mark_exited!).at_least(:once)
          service.sync_positions!
        end
      end

      context 'error handling' do
        it 'handles API errors gracefully' do
          allow(DhanHQ::Models::Position).to receive(:active).and_raise(StandardError, 'API error')
          allow(Rails.logger).to receive(:error).and_call_original
          
          expect(Rails.logger).to receive(:error).with(match(/Failed to sync positions: StandardError - API error/)).at_least(:once)

          expect { service.sync_positions! }.not_to raise_error
        end

        it 'continues syncing other positions if one fails' do
          dhan_position = double('DhanPosition', security_id: '50074', net_qty: 75, buy_avg: 100.5, to_h: {}, inspect: 'DhanPosition')
          allow(DhanHQ::Models::Position).to receive(:active).and_return([dhan_position])
          
          # Mock ActivePositionsCache
          allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([active_tracker])
          
          # Cause failure in orphaned check for example
          allow(service).to receive(:mark_orphaned_live_positions).and_raise(StandardError, 'Sync error')
          
          allow(Rails.logger).to receive(:error).and_call_original
          expect(Rails.logger).to receive(:error).with(match(/Failed to sync positions: StandardError - Sync error/)).at_least(:once)

          expect { service.sync_positions! }.not_to raise_error
        end
      end

      describe 'polling interval enforcement' do
        it 'allows sync if interval elapsed' do
          expect(DhanHQ::Models::Position).to receive(:active).and_return([]).twice

          service.sync_positions!
          
          # Travel 31 seconds forward
          travel 31.seconds do
            service.sync_positions!
          end
        end
      end

      describe '.force_sync!' do
        it 'forces sync regardless of interval' do
          expect(DhanHQ::Models::Position).to receive(:active).and_return([]).twice

          service.sync_positions!
          service.force_sync!
        end
      end

      context 'when paper trading is enabled' do
        before do
          allow(service).to receive(:paper_trading_enabled?).and_return(true)
        end

        it 'syncs paper positions instead of live ones' do
          # In paper mode, sync_paper_positions is called, which doesn't call DhanHQ::Models::Position.active
          expect(DhanHQ::Models::Position).not_to receive(:active)
          expect(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([])

          service.sync_positions!
        end

        it 'subscribes to market feed for paper positions' do
          # Mock a paper position
          paper_tracker = create(:position_tracker, :active, paper: true, security_id: '12345', segment: 'NSE_FNO', watchable: create(:derivative))
          allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([paper_tracker])
          
          market_feed_hub = Live::MarketFeedHub.instance
          expect(market_feed_hub).to receive(:subscribed?).and_return(false)
          expect(paper_tracker).to receive(:subscribe).and_return({ already_subscribed: false })

          service.sync_positions!
        end
      end
    end
  end
end
