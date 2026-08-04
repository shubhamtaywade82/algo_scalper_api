# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard do
  let(:daily_limits) { instance_double(Live::DailyLimits) }
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

  before do
    allow(Live::DailyLimits).to receive(:new).and_return(daily_limits)
    allow(daily_limits).to receive(:can_trade?).and_return({ allowed: true, reason: nil })
  end

  describe 'EPIC F — F1: Place Entry Order & Subscribe Option Tick' do
    describe '.try_enter' do
      before do
        allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nifty_instrument)
        allow(described_class).to receive(:ensure_ws_connection!)
        allow(Capital::Allocator).to receive(:qty_for).and_return(75)
        allow(Orders.config).to receive(:place_market).and_return(double(order_id: 'ORD123456'))
        allow(described_class).to receive_messages(extract_order_no: 'ORD123456', exposure_ok?: true, cooldown_active?: false)
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

  describe '.build_base_meta' do
    subject(:meta) { described_class.send(:build_base_meta, index_cfg: index_cfg, pick: pick, direction: direction) }

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

    it 'pins a config snapshot for the position' do
      expect(meta[:config_snapshot]).to be_a(Hash).and(include(:risk))
    end

    it 'excludes credential sections from the pinned snapshot' do
      expect(meta[:config_snapshot].keys).not_to include(:dhanhq, :telegram, :ai)
    end
  end

  describe '.try_enter' do
    context 'when pipeline fails' do
      let(:blocked_reason) { 'pipeline_reason' }
      before do
        allow(Entries::EntryGuard.entry_guard_pipeline).to receive(:run).and_return({ blocked: blocked_reason })
      end

      it 'blocks entry and records outcome' do
        expect(described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, signal: signal)).to be false
        expect(signal).to have_received(:record_entry_outcome).with('blocked', blocked_reason)
      end
    end

    context 'when order execution fails' do
      before do
        allow(Entries::OrderExecutionService).to receive(:call).and_return({ error: 'order_failed' })
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
    end

      context 'when quantity calculation fails' do
        it 'returns false when quantity is zero' do
          allow(Capital::Allocator).to receive(:qty_for).and_return(0)

          expect do
            result = described_class.try_enter(
              index_cfg: index_cfg,
              pick: pick,
              direction: :bullish
            )

            expect(result).to be false
          end.not_to change(PositionTracker, :count)
        end
      end
    end
  end
end

RSpec.describe Entries::Guards::ExposureGuard do
  describe '.exposure_ok?' do
    let(:db_instrument) { create(:instrument, segment: 'derivatives') }

    it 'returns true when under limit' do
      expect(described_class.exposure_ok?(instrument: db_instrument, side: 'long_ce', max_same_side: 3)).to be true
    end

    it 'returns false when at limit' do
      create_list(:position_tracker, 2, instrument: db_instrument, status: 'active', side: 'long_ce', segment: 'NSE_FNO', security_id: '999')
      expect(described_class.exposure_ok?(instrument: db_instrument, side: 'long_ce', max_same_side: 2)).to be false
    end

    context 'with rupee-based exposure limit configured' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          quantity: 100,
          ltp: 150.0 # proposed outlay = 150 * 100 = 15,000
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            max_exposure_rupees: {
              'NIFTY' => 20000.0
            }
          }
        })
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

      it 'returns false if total exposure exceeds limit' do
        # Create an existing active position of NIFTY options with outlay of 10,000
        create(:position_tracker, instrument: db_instrument, status: 'active', index_key: 'NIFTY', segment: 'NSE_FNO', quantity: 100, entry_price: 100.0)
        # Total = 10,000 (current) + 15,000 (proposed) = 25,000 > 20,000 limit
        expect(described_class.exposure_ok?(instrument: db_instrument, side: 'long_ce', max_same_side: 3, context: context)).to be false
      end
    end
  end

  describe 'apply_bos_metadata!' do
    let(:meta_hash) { { index_key: 'NIFTY' } }
    let(:entry_price) { 200.0 }
    let(:quantity) { 50 }

    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: { sl_pct: 0.12 },
        indices: [{ key: 'NIFTY', segment: 'IDX_I', sid: '13' }]
      })
    end

    context 'supertrend contract' do
      let(:bos_context) do
        {
          confirmed_at: Time.current,
          direction: 'long_pe',
          bos_id: 'st_NIFTY_123',
          timeframe: '1m',
          origin_swing: { price: 200.0, index: 0 },
          entry_underlying_price: 23850.0
        }
      end
      let(:entry_metadata) do
        {
          entry_contract: 'supertrend_machine_v1',
          entry_underlying_price: 23850.0
        }
      end

      it 'stores entry_underlying_price from entry_metadata' do
        described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                             entry_price: entry_price, quantity: quantity)
        expect(meta_hash[:entry_underlying_price]).to eq(23850.0)
      end

      it 'calculates initial_sl_pct in premium domain (≈12%)' do
        described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                             entry_price: entry_price, quantity: quantity)
        expect(meta_hash[:initial_sl_pct]).to be_within(1.0).of(12.0)
      end

      it 'calculates premium_stop_price as positive below entry' do
        described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                             entry_price: entry_price, quantity: quantity)
        expect(meta_hash[:premium_stop_price]).to be > 0
        expect(meta_hash[:premium_stop_price]).to be < entry_price
      end
    end

    context 'BOS contract' do
      let(:bos_context) do
        {
          confirmed_at: Time.current,
          direction: 'long_pe',
          bos_id: 'bos_NIFTY_123',
          timeframe: '5m',
          origin_swing: { price: 23800.0, index: 0 },
          entry_underlying_price: 23850.0
        }
      end
      let(:entry_metadata) do
        { entry_contract: 'bos_machine_v1' }
      end

      it 'uses premium domain for stops (not underlying domain)' do
        described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                             entry_price: entry_price, quantity: quantity)
        expect(meta_hash[:initial_sl_pct]).to be_within(1.0).of(12.0)
      end

      it 'stores structure_invalidation_price in underlying domain' do
        described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                             entry_price: entry_price, quantity: quantity)
        expect(meta_hash[:structure_invalidation_price]).to eq(23800.0)
      end

      it 'stores entry_underlying_price from bos_context' do
        described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                             entry_price: entry_price, quantity: quantity)
        expect(meta_hash[:entry_underlying_price]).to eq(23850.0)
      end
    end

    context 'when entry_underlying_price is nil' do
      let(:bos_context) do
        {
          confirmed_at: Time.current,
          direction: 'long_pe',
          bos_id: 'st_NIFTY_123',
          timeframe: '1m',
          origin_swing: { price: 200.0, index: 0 },
          entry_underlying_price: nil
        }
      end
      let(:entry_metadata) do
        { entry_contract: 'supertrend_machine_v1', entry_underlying_price: nil }
      end

      it 'falls back to TickQuery for underlying price' do
        tick = double(ltp: 23900.0)
        allow(Live::TickQuery).to receive(:for_security)
          .with(segment: 'IDX_I', security_id: '13')
          .and_return(tick)

        described_class.send(:apply_bos_metadata!, meta_hash, bos_context, entry_metadata,
                             entry_price: entry_price, quantity: quantity)
        expect(meta_hash[:entry_underlying_price]).to eq(23900.0)
      end
    end
  end
end
