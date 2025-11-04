# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::PositionSyncService do
  let(:service) { described_class.instance }
  let(:instrument) { create(:instrument, :nifty_future, security_id: '9999') }
  let(:pending_tracker) do
    create(
      :position_tracker,
      instrument: instrument,
      order_no: 'ORD123456',
      security_id: '50074',
      segment: 'NSE_FNO',
      status: 'pending',
      quantity: 75,
      entry_price: 100.0
    )
  end

  describe 'EPIC F — F1: Place Entry Order & Subscribe Option Tick' do
    describe '.sync_positions!' do
      before do
        allow(service).to receive(:should_sync?).and_return(true)
      end

      context 'when syncing positions' do
        it 'syncs within polling interval (30 seconds)' do
          allow(service).to receive(:should_sync?).and_call_original
          service.instance_variable_set(:@last_sync, nil)

          allow(DhanHQ::Models::Position).to receive(:active).and_return([])
          allow(PositionTracker).to receive(:active).and_return(PositionTracker.none)

          start_time = Time.current
          service.sync_positions!
          elapsed = Time.current - start_time

          expect(elapsed).to be < 30.seconds
        end

        it 'only queries active trackers, not pending ones' do
          allow(DhanHQ::Models::Position).to receive(:active).and_return([])
          expect(PositionTracker).to receive(:active).and_return(PositionTracker.none)

          service.sync_positions!
        end
      end

      context 'when no positions match' do
        it 'does not update trackers if no DhanHQ positions found' do
          allow(DhanHQ::Models::Position).to receive(:active).and_return([])
          allow(PositionTracker).to receive(:active).and_return(PositionTracker.where(id: pending_tracker.id))

          expect(pending_tracker).not_to receive(:mark_active!)

          service.sync_positions!
        end
      end

      context 'when tracker already active' do
        let(:active_tracker) do
          create(
            :position_tracker,
            instrument: instrument,
            order_no: 'ORD123457',
            security_id: '50075',
            segment: 'NSE_FNO',
            status: 'active',
            quantity: 75
          )
        end

        it 'does not call mark_active! on already active tracker' do
          dhan_position = double(
            'DhanPosition',
            security_id: '50075',
            trading_symbol: 'NIFTY18500PE',
            exchange_segment: 'NSE_FNO',
            net_qty: 75,
            buy_avg: 99.5,
            product_type: 'INTRADAY',
            position_type: 'LONG'
          )

          allow(DhanHQ::Models::Position).to receive(:active).and_return([dhan_position])
          allow(PositionTracker).to receive(:active).and_return(PositionTracker.where(id: active_tracker.id))

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
          allow(Derivative).to receive(:find_by).and_return(
            create(:derivative, security_id: '50076', instrument: instrument)
          )
        end

        it 'creates PositionTracker for untracked positions' do
          allow(DhanHQ::Models::Position).to receive(:active).and_return([untracked_position])
          allow(PositionTracker).to receive(:active).and_return(PositionTracker.none)

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
          allow(PositionTracker).to receive(:active).and_return(PositionTracker.none)

          market_feed_hub = Live::MarketFeedHub.instance
          expect(market_feed_hub).to receive(:subscribe).with(
            segment: 'NSE_FNO',
            security_id: '50076'
          )

          service.sync_positions!
        end
      end

      context 'when tracker exists but position closed in DhanHQ' do
        let(:active_tracker) do
          create(
            :position_tracker,
            instrument: instrument,
            order_no: 'ORD123458',
            security_id: '50077',
            segment: 'NSE_FNO',
            status: 'active',
            quantity: 75
          )
        end

        it 'marks tracker as exited when position not found in DhanHQ' do
          allow(DhanHQ::Models::Position).to receive(:active).and_return([])
          trackers = PositionTracker.where(id: active_tracker.id)
          allow(PositionTracker).to receive(:active).and_return(trackers)

          expect_any_instance_of(PositionTracker).to receive(:mark_exited!).at_least(:once)

          service.sync_positions!
        end
      end

      context 'error handling' do
        it 'handles API errors gracefully' do
          allow(DhanHQ::Models::Position).to receive(:active).and_raise(StandardError, 'API error')

          expect(Rails.logger).to receive(:error).with(
            match(/Failed to sync positions: StandardError - API error/)
          ).at_least(:once)
          expect(Rails.logger).to receive(:error).with(
            match(/Backtrace:/)
          ).at_least(:once)

          expect { service.sync_positions! }.not_to raise_error
        end

        it 'continues syncing other positions if one fails' do
          allow(Derivative).to receive(:find_by).and_raise(StandardError, 'Database error')

          untracked_position1 = double(
            'DhanPosition',
            security_id: '50076',
            trading_symbol: 'NIFTY18550CE',
            exchange_segment: 'NSE_FNO',
            net_qty: 75,
            buy_avg: 102.0,
            product_type: 'INTRADAY',
            position_type: 'LONG',
            to_h: {}
          )

          allow(DhanHQ::Models::Position).to receive(:active).and_return([untracked_position1])
          allow(PositionTracker).to receive(:active).and_return(PositionTracker.none)

          expect(Rails.logger).to receive(:error).at_least(:once)

          service.sync_positions!
        end
      end

      context 'polling interval enforcement' do
        it 'skips sync if called within interval' do
          service.instance_variable_set(:@last_sync, 15.seconds.ago)

          allow(service).to receive(:should_sync?).and_call_original

          expect(DhanHQ::Models::Position).not_to receive(:active)

          service.sync_positions!
        end

        it 'allows sync if interval elapsed' do
          service.instance_variable_set(:@last_sync, 31.seconds.ago)

          allow(service).to receive(:should_sync?).and_call_original
          allow(DhanHQ::Models::Position).to receive(:active).and_return([])
          allow(PositionTracker).to receive(:active).and_return(PositionTracker.none)

          service.sync_positions!

          expect(service.instance_variable_get(:@last_sync)).to be_within(1.second).of(Time.current)
        end
      end
    end

    describe '.force_sync!' do
      it 'forces sync regardless of interval' do
        service.instance_variable_set(:@last_sync, 10.seconds.ago)

        allow(DhanHQ::Models::Position).to receive(:active).and_return([])
        allow(PositionTracker).to receive(:active).and_return(PositionTracker.none)

        expect(service).to receive(:should_sync?).and_return(true)

        service.force_sync!
      end
    end
  end
end
