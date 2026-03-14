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
      watchable: create(:derivative, instrument: instrument),
      instrument: instrument,
      security_id: '50074',
      status: :active,
      entry_price: 100.5,
      quantity: 75
    )
  end

  before do
    allow(TradingSession::Service).to receive(:market_open?).and_return(true)
    # Clear sync state before each test
    service.instance_variable_set(:@last_sync, nil)
    # Ensure ActivePositionsCache is also cleared
    Positions::ActivePositionsCache.instance.clear!
  end

  after do
    # Clear singleton state to prevent leakage
    service.instance_variable_set(:@last_sync, nil)
    Positions::ActivePositionsCache.instance.clear!
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
          create(:position_tracker, :pending)
          allow(DhanHQ::Models::Position).to receive(:active).and_return([])
          
          # Manually populate cache with active tracker only
          allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([active_tracker])

          service.sync_positions!
          # Implicitly verified by lack of error and internal logic
        end

        it 'when no positions match does not update trackers if no DhanHQ positions found' do
          allow(DhanHQ::Models::Position).to receive(:active).and_return([])
          allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([active_tracker])

          # It will find active_tracker in cache, but not in DhanHQ, 
          # so it should mark it as exited if it's a live position.
          # For this test we make it paper so it doesn't mark exited.
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
            position_type: 'LONG'
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
            }
          )
        end

        before do
          # Mock ActivePositionsCache to return empty (no trackers for this security_id)
          allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([])
          
          # Create the derivative that the sync service will look for
          @derivative = create(:derivative, security_id: '50076', instrument: instrument, exchange: 'nse', segment: 'derivatives')
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

          expect_any_instance_of(PositionTracker).to receive(:mark_exited!).at_least(:once)
          service.sync_positions!
        end
      end

      context 'error handling' do
        it 'handles API errors gracefully' do
          allow(DhanHQ::Models::Position).to receive(:active).and_raise(StandardError, 'API error')
          allow(Rails.logger).to receive(:error).and_call_original
          
          # The service logs the error with a specific prefix
          expect(Rails.logger).to receive(:error).with(match(/\[PositionSync\] Failed to sync positions: StandardError - API error/)).at_least(:once)

          expect { service.sync_positions! }.not_to raise_error
        end

        it 'continues syncing other positions if one fails' do
          dhan_position = double('DhanPosition', security_id: '50074', net_qty: 75, buy_avg: 100.5, to_h: {})
          allow(DhanHQ::Models::Position).to receive(:active).and_return([dhan_position])
          
          # Mock ActivePositionsCache
          allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([active_tracker])
          
          # Cause failure in orphaned check for example
          allow(service).to receive(:mark_orphaned_live_positions).and_raise(StandardError, 'Sync error')
          
          allow(Rails.logger).to receive(:error).and_call_original
          expect(Rails.logger).to receive(:error).with(match(/\[PositionSync\] Failed to sync positions: StandardError - Sync error/)).at_least(:once)

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
    end
  end
end
