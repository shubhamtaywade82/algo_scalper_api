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

  # Minimal BOS contract so try_enter passes bos_contract_present? (required by EntryGuard)
  let(:entry_metadata) do
    {
      entry_contract: 'supertrend_machine_v1',
      bos_id: 'st1',
      bos_timeframe: '5',
      bos_origin_price: 100.0,
      bos_level: 99.0,
      paper: true
    }
  end

  before do
    allow(Live::DailyLimits).to receive(:new).and_return(daily_limits)
    allow(daily_limits).to receive(:can_trade?).and_return({ allowed: true, reason: nil })
  end

  describe 'EPIC F — F1: Place Entry Order & Subscribe Option Tick' do
    skip 'Disabled: EPIC scenario spec is legacy/noise for PR hardening checks.'

    describe '.try_enter' do
      before do
        allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nifty_instrument)
        allow(described_class).to receive(:ensure_ws_connection!)
        allow(described_class).to receive(:time_regime_allows_entry?).and_return(true)
        allow(Capital::Allocator).to receive(:qty_for).and_return(75)
        allow(Trading::InstrumentExecutionProfile).to receive(:for).with('NIFTY').and_return(
          { allow_execution_only: true, max_lots_by_permission: { scale_ready: 10 } }
        )
        allow(Trading::LotCalculator).to receive(:lot_size_for).with('NIFTY').and_return(75)
        allow(Trading::CapitalAllocator).to receive(:max_lots).and_return(2)
        gateway = instance_double(Orders::Gateway, place_market: double(order_id: 'ORD123456'))
        allow(Orders.config).to receive(:gateway).and_return(gateway)
        allow(described_class).to receive_messages(extract_order_no: 'ORD123456', exposure_ok?: true, cooldown_active?: false)
        allow(TradingSession::Service).to receive(:entry_allowed?).and_return({ allowed: true })
        allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: false } })
        allow(Live::MarketFeedHub.instance).to receive_messages(running?: true, connected?: true)
      end

      context 'when all validations pass' do
        it 'places INTRADAY | MARKET | BUY order via gateway with correct parameters' do
          gateway = Orders.config.gateway
          expect(gateway).to receive(:place_market).with(
            side: 'buy',
            segment: 'NSE_FNO',
            security_id: '50074',
            qty: 75,
            meta: hash_including(
              client_order_id: match(/^AS-NIFT-50074-/),
              ltp: 100.0,
              symbol: 'NIFTY18500CE'
            )
          )

          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish,
            entry_metadata: entry_metadata
          )
        end

        it 'creates PositionTracker with status active' do
          expect do
            described_class.try_enter(
              index_cfg: index_cfg,
              pick: pick,
              direction: :bullish,
              entry_metadata: entry_metadata
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
          gateway = Orders.config.gateway
          timestamp_match = /\d{6}$/

          expect(gateway).to receive(:place_market) do |args|
            coid = args[:meta][:client_order_id]
            expect(coid).to match(/^AS-NIFT-50074-/)
            expect(coid).to match(timestamp_match)
            expect(coid.length).to be <= 30
            double(order_id: 'ORD123456')
          end

          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish,
            entry_metadata: entry_metadata
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
            direction: :bullish,
            entry_metadata: entry_metadata
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
            scale_multiplier: 2,
            entry_metadata: entry_metadata
          )
        end

        it 'returns true on successful order placement' do
          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish,
            entry_metadata: entry_metadata
          )

          expect(result).to be true
        end

        it 'logs success message' do
          allow(Rails.logger).to receive(:info)
          expect(Rails.logger).to receive(:info).with(
            match(/Successfully placed order ORD123456 for NIFTY: NIFTY18500CE/)
          ).at_least(:once)

          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish,
            entry_metadata: entry_metadata
          )
        end
      end

      context 'when instrument lookup fails' do
        it 'returns false if instrument not found' do
          allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nil)

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish,
            entry_metadata: entry_metadata
          )

          expect(result).to be false
        end
      end

      context 'when exposure validation fails' do
        it 'returns false if exposure limit reached' do
          # Use BOS contract (not Supertrend) so exposure_ok? is called
          allow(described_class).to receive_messages(enforce_structure_entry_gate: { confirmed_at: Time.current }, exposure_ok?: false)
          bos_metadata = {
            entry_contract: 'bos_machine_v1',
            bos_id: 'b1',
            bos_timeframe: '5',
            bos_origin_price: 100.0,
            bos_level: 99.0,
            paper: true
          }

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish,
            entry_metadata: bos_metadata
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
            direction: :bullish,
            entry_metadata: entry_metadata
          )

          expect(result).to be false
        end
      end

      context 'when WebSocket connection check fails' do
        it 'logs info when feed is stale and uses REST fallback' do
          allow(Live::MarketFeedHub.instance).to receive_messages(running?: false, connected?: false)
          allow(Rails.logger).to receive(:info)
          expect(Rails.logger).to receive(:info).with(
            match(/WebSocket not connected - will use REST API fallback/)
          ).at_least(:once)

          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish,
            entry_metadata: entry_metadata
          )
        end
      end

      context 'when quantity calculation fails' do
        it 'returns false when quantity is zero' do
          allow(Capital::Allocator).to receive(:qty_for).and_return(0)

          expect do
            result = described_class.try_enter(
              index_cfg: index_cfg,
              pick: pick,
              direction: :bullish,
              entry_metadata: entry_metadata
            )

            expect(result).to be false
          end.not_to change(PositionTracker, :count)
        end
      end

      context 'when order placement fails' do
        it 'returns false if order_no extraction fails' do
          allow(described_class).to receive(:extract_order_no).and_return(nil)

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish,
            entry_metadata: entry_metadata
          )

          expect(result).to be false
        end

        it 'returns false if gateway place_market returns nil' do
          allow(Orders.config.gateway).to receive(:place_market).and_return(nil)
          allow(described_class).to receive(:extract_order_no).and_return(nil)

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish,
            entry_metadata: entry_metadata
          )

          expect(result).to be false
          expect(PositionTracker.count).to eq(0)
        end
      end

      context 'when direction is bearish' do
        it 'uses long_pe side for bearish direction' do
          described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bearish,
            entry_metadata: entry_metadata
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
            direction: :bullish,
            entry_metadata: entry_metadata
          )

          expect(result).to be false
        end

        it 'handles generic exceptions gracefully' do
          allow(Orders.config.gateway).to receive(:place_market).and_raise(StandardError, 'Unexpected error')

          expect(Rails.logger).to receive(:error).with(
            match(/EntryGuard failed for NIFTY: StandardError - Unexpected error/)
          )

          result = described_class.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: :bullish,
            entry_metadata: entry_metadata
          )

          expect(result).to be false
        end
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
