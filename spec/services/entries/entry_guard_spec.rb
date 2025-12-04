# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard do
  let(:daily_limits) { instance_double(Live::DailyLimits) }

  before do
    allow(Live::DailyLimits).to receive(:new).and_return(daily_limits)
    allow(daily_limits).to receive(:can_trade?).and_return({ allowed: true, reason: nil })
  end
  let(:nifty_instrument) { create(:instrument, :nifty_future, security_id: '9999', symbol_name: 'NIFTY') }
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'IDX_I',
      sid: '9999',
      capital_alloc_pct: 0.30,
      max_same_side: 2,
      cooldown_sec: 180
    }
  end
  let(:pick) do
    {
      symbol: 'NIFTY18500CE',
      security_id: '50074',
      segment: 'NSE_FNO',
      ltp: 100.0,
      lot_size: 75
    }
  end

  describe 'EPIC F — F1: Place Entry Order & Subscribe Option Tick' do
    describe '.try_enter' do
      before do
        allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nifty_instrument)
        allow(described_class).to receive(:ensure_ws_connection!)
        allow(Capital::Allocator).to receive(:qty_for).and_return(75)
        allow(Orders.config).to receive(:place_market).and_return(double(order_id: 'ORD123456'))
        allow(described_class).to receive(:extract_order_no).and_return('ORD123456')
        allow(described_class).to receive(:exposure_ok?).and_return(true)
        allow(described_class).to receive(:cooldown_active?).and_return(false)
        # Mock trading session and paper trading
        allow(TradingSession::Service).to receive(:entry_allowed?).and_return({ allowed: true })
        allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: false } })
        # Mock MarketFeedHub
        allow(Live::MarketFeedHub.instance).to receive_messages(running?: true, connected?: true)
      end

      context 'when all validations pass' do
        it 'places INTRADAY | MARKET | BUY order with correct parameters' do
          expect(Orders.config).to receive(:place_market).with(
            side: 'buy',
            segment: 'NSE_FNO',
            security_id: '50074',
            qty: 75,
            meta: hash_including(
              client_order_id: match(/^AS-NIFT-50074-/),
              ltp: 100.0
            )
          )

          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )
        end

        it 'creates PositionTracker with status active' do
          expect do
            described_class.try_enter(
              index_cfg: index_cfg,
              pick: pick,
              direction: :bullish
            )
          end.to change(PositionTracker, :count).by(1)

          tracker = PositionTracker.last
          expect(tracker.status).to eq('active')
          expect(tracker.order_no).to eq('ORD123456')
          expect(tracker.security_id).to eq('50074')
          expect(tracker.symbol).to eq('NIFTY18500CE')
          expect(tracker.side).to eq('long_ce')
          expect(tracker.quantity).to eq(75)
          expect(tracker.entry_price).to eq(BigDecimal('100.0'))
        end

        it 'builds client order ID in correct format' do
          allow(described_class).to receive(:build_client_order_id).and_call_original
          timestamp_match = /\d{6}$/

          expect(Orders.config).to receive(:place_market) do |args|
            coid = args[:meta][:client_order_id]
            expect(coid).to match(/^AS-NIFT-50074-/)
            expect(coid).to match(timestamp_match)
            expect(coid.length).to be <= 30
            double(order_id: 'ORD123456')
          end

          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )
        end

        it 'calculates quantity using Capital::Allocator' do
          expect(Capital::Allocator).to receive(:qty_for).with(
            index_cfg: index_cfg,
            entry_price: 100.0,
            derivative_lot_size: 75,
            scale_multiplier: 1
          ).and_return(150)

          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )
        end

        it 'applies scale multiplier correctly' do
          expect(Capital::Allocator).to receive(:qty_for).with(
            index_cfg: index_cfg,
            entry_price: 100.0,
            derivative_lot_size: 75,
            scale_multiplier: 2
          ).and_return(150)

          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish,
            scale_multiplier: 2
          )
        end

        it 'returns true on successful order placement' do
          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )

          expect(result).to be true
        end

        it 'logs success message' do
          allow(Rails.logger).to receive(:info) # Allow all info logs
          expect(Rails.logger).to receive(:info).with(
            match(/Successfully placed order ORD123456 for NIFTY: NIFTY18500CE/)
          ).at_least(:once)

          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )
        end
      end

      context 'when instrument lookup fails' do
        it 'returns false if instrument not found' do
          allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nil)

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )

          expect(result).to be false
        end
      end

      context 'when exposure validation fails' do
        it 'returns false if exposure limit reached' do
          allow(described_class).to receive(:exposure_ok?).and_return(false)

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )

          expect(result).to be false
        end
      end

      context 'when cooldown is active' do
        it 'returns false if cooldown active' do
          allow(described_class).to receive(:cooldown_active?).and_return(true)

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )

          expect(result).to be false
        end
      end

      context 'when WebSocket connection check fails' do
        it 'returns false if WebSocket not running' do
          allow(described_class).to receive(:ensure_ws_connection!).and_raise(
            Live::FeedHealthService::FeedStaleError.new(
              feed: :ws_connection,
              last_seen_at: nil,
              threshold: 0,
              last_error: nil
            )
          )

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )

          expect(result).to be false
        end

        it 'logs warning when feed is stale' do
          # NOTE: The code no longer blocks on WebSocket errors - it uses REST API fallback
          # This test is kept for historical reference but the behavior has changed
          # The code now logs info messages instead of warnings for WebSocket issues
          allow(Live::MarketFeedHub.instance).to receive_messages(running?: false, connected?: false)
          allow(Rails.logger).to receive(:info) # Allow all info logs
          expect(Rails.logger).to receive(:info).with(
            match(/WebSocket not connected - will use REST API fallback/)
          ).at_least(:once)

          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )
        end
      end

      context 'when quantity calculation fails' do
        it 'returns false if quantity is zero' do
          allow(Capital::Allocator).to receive(:qty_for).and_return(0)

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )

          expect(result).to be false
        end

        it 'falls back to paper mode when enabled and live balance is insufficient' do
          allow(Capital::Allocator).to receive(:qty_for).and_return(0)
          allow(described_class).to receive(:paper_trading_enabled?).and_return(false)
          allow(described_class).to receive(:auto_paper_fallback_enabled?).and_return(true)
          allow(described_class).to receive(:insufficient_live_balance?).and_return(true)

          expect {
            described_class.try_enter(
              index_cfg: index_cfg,
              pick: pick,
              direction: :bullish
            )
          }.to change(PositionTracker, :count).by(1)

          tracker = PositionTracker.last
          expect(tracker.paper?).to be true
          expect(tracker.meta['fallback_to_paper']).to be true
          expect(tracker.quantity).to eq(pick[:lot_size])
        end
      end

      context 'when order placement fails' do
        it 'returns false if order_no extraction fails' do
          allow(described_class).to receive(:extract_order_no).and_return(nil)

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )

          expect(result).to be false
        end

        it 'returns false if order placement returns nil' do
          allow(Orders.config).to receive(:place_market).and_return(nil)
          # Override the before block stub - when response is nil, extract_order_no should return nil
          allow(described_class).to receive(:extract_order_no).and_return(nil)

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )

          expect(result).to be false
          expect(PositionTracker.count).to eq(0) # No tracker created
        end
      end

      context 'when direction is bearish' do
        it 'uses long_pe side for bearish direction' do
          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bearish
          )

          tracker = PositionTracker.last
          expect(tracker.side).to eq('long_pe')
        end
      end

      context 'when handling errors' do
        it 'handles RecordInvalid gracefully' do
          invalid_record = PositionTracker.new
          invalid_record.errors.add(:base, 'Validation failed')
          allow(PositionTracker).to receive(:create!).and_raise(
            ActiveRecord::RecordInvalid.new(invalid_record)
          )

          expect(Rails.logger).to receive(:error).with(
            match(/Failed to persist tracker for order ORD123456/)
          )

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )

          # NOTE: create_tracker! catches RecordInvalid and returns nil,
          # so try_enter checks `unless tracker` and returns false.
          expect(result).to be false
        end

        it 'handles generic exceptions gracefully' do
          allow(Orders.config).to receive(:place_market).and_raise(StandardError, 'Unexpected error')

          expect(Rails.logger).to receive(:error).with(
            match(/EntryGuard failed for NIFTY: StandardError - Unexpected error/)
          )

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish
          )

          expect(result).to be false
        end
      end
    end
  end
end
