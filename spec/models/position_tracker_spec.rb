# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PositionTracker do
  let(:instrument) { create(:instrument, :nifty_future) }
  let(:tracker) do
    create(
      :position_tracker,
      :pending,
      instrument: instrument,
      order_no: 'ORD123456',
      security_id: '50074',
      segment: 'NSE_FNO',
      quantity: 75,
      entry_price: 100.0
    )
  end

  describe 'EPIC F — F1: Place Entry Order & Subscribe Option Tick' do
    let(:mock_redis) { instance_double('Redis', set: true, get: nil, del: true) }
    let(:redis_cache) { Live::RedisPnlCache.instance }

    before do
      allow(Redis).to receive(:new).and_return(mock_redis)
      redis_cache.instance_variable_set(:@redis, mock_redis)
    end

    after do
      redis_cache.instance_variable_set(:@redis, nil)
    end

    describe '#mark_active!' do
      context 'when order is filled' do
        it 'updates status to active' do
          tracker.mark_active!(avg_price: 101.5, quantity: 75)

          expect(tracker.reload.status).to eq('active')
        end

        it 'sets avg_price and updates entry_price if missing' do
          tracker.update(entry_price: nil)
          tracker.mark_active!(avg_price: 101.5, quantity: 75)

          tracker.reload
          expect(tracker.avg_price).to eq(BigDecimal('101.5'))
          expect(tracker.entry_price).to eq(BigDecimal('101.5'))
        end

        it 'preserves existing entry_price if present' do
          tracker.mark_active!(avg_price: 101.5, quantity: 75)

          tracker.reload
          expect(tracker.avg_price).to eq(BigDecimal('101.5'))
          expect(tracker.entry_price).to eq(BigDecimal('100.0')) # Preserved
        end

        it 'updates quantity' do
          tracker.mark_active!(avg_price: 101.5, quantity: 100)

          expect(tracker.reload.quantity).to eq(100)
        end

        it 'subscribes to option tick feed' do
          market_feed_hub = Live::MarketFeedHub.instance
          expect(market_feed_hub).to receive(:subscribe).with(
            segment: 'NSE_FNO',
            security_id: '50074'
          )

          tracker.mark_active!(avg_price: 101.5, quantity: 75)
        end

        it 'subscribes within 1s of fill detection' do
          start_time = Time.current
          market_feed_hub = Live::MarketFeedHub.instance

          allow(market_feed_hub).to receive(:subscribe) do
            elapsed = Time.current - start_time
            expect(elapsed).to be < 1.second
          end

          tracker.mark_active!(avg_price: 101.5, quantity: 75)
        end
      end

      context 'when avg_price is nil' do
        it 'handles nil avg_price gracefully' do
          tracker.mark_active!(avg_price: nil, quantity: 75)

          tracker.reload
          expect(tracker.status).to eq('active')
          expect(tracker.avg_price).to be_nil
          expect(tracker.quantity).to eq(75)
        end
      end
    end

    describe '#subscribe' do
      context 'when segment and security_id are present' do
        it 'calls MarketFeedHub.subscribe with correct parameters' do
          market_feed_hub = Live::MarketFeedHub.instance
          expect(market_feed_hub).to receive(:subscribe).with(
            segment: 'NSE_FNO',
            security_id: '50074'
          )

          tracker.subscribe
        end

        it 'uses instrument exchange_segment if segment not present' do
          tracker.update(segment: nil)
          allow(instrument).to receive(:exchange_segment).and_return('NSE_FNO')

          market_feed_hub = Live::MarketFeedHub.instance
          expect(market_feed_hub).to receive(:subscribe).with(
            segment: 'NSE_FNO',
            security_id: '50074'
          )

          tracker.subscribe
        end
      end

      context 'when segment or security_id missing' do
        it 'does not subscribe if segment is missing' do
          tracker.update(segment: nil)
          allow(instrument).to receive(:exchange_segment).and_return(nil)

          market_feed_hub = Live::MarketFeedHub.instance
          expect(market_feed_hub).not_to receive(:subscribe)

          tracker.subscribe
        end

        it 'does not subscribe if security_id is missing' do
          tracker.update(security_id: nil)

          market_feed_hub = Live::MarketFeedHub.instance
          expect(market_feed_hub).not_to receive(:subscribe)

          tracker.subscribe
        end
      end
    end

    describe '#unsubscribe' do
      it 'unsubscribes from option tick feed' do
        market_feed_hub = Live::MarketFeedHub.instance
        expect(market_feed_hub).to receive(:unsubscribe).with(
          segment: 'NSE_FNO',
          security_id: '50074'
        )

        tracker.unsubscribe
      end

      it 'unsubscribes underlying instrument if option' do
        underlying = create(:instrument, :nifty_index)
        allow(tracker.instrument).to receive(:underlying_symbol).and_return('NIFTY')
        allow(Instrument).to receive(:find_by).and_return(underlying)

        market_feed_hub = Live::MarketFeedHub.instance
        expect(market_feed_hub).to receive(:unsubscribe).with(
          segment: 'NSE_FNO',
          security_id: '50074'
        )
        expect(market_feed_hub).to receive(:unsubscribe).with(
          segment: 'IDX_I',
          security_id: underlying.security_id
        )

        tracker.unsubscribe
      end
    end

    describe 'status transitions' do
      it 'starts as pending after order placement' do
        expect(tracker.status).to eq('pending')
      end

      it 'transitions to active after mark_active!' do
        tracker.mark_active!(avg_price: 101.5, quantity: 75)
        expect(tracker.reload.status).to eq('active')
      end

      it 'transitions to cancelled after mark_cancelled!' do
        tracker.mark_cancelled!
        expect(tracker.reload.status).to eq('cancelled')
      end

      it 'transitions to exited after mark_exited!' do
        tracker.update(status: 'active')
        tracker.mark_exited!
        expect(tracker.reload.status).to eq('exited')
      end
    end
  end
end
