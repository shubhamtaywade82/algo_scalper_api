# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Factories::PositionTrackerFactory do
  let(:instrument) { create(:instrument, :nifty_index) }
  let(:derivative) { create(:derivative, instrument: instrument) }
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'IDX_I',
      sid: instrument.security_id,
      max_same_side: 2
    }
  end
  let(:pick) do
    {
      symbol: 'NIFTY18500CE',
      security_id: '50074',
      segment: 'NSE_FNO',
      ltp: 100.0,
      lot_size: 75,
      derivative_id: derivative.id
    }
  end

  before do
    allow(Live::RedisPnlCache.instance).to receive(:store_pnl)
    allow(Positions::ActiveCache.instance).to receive(:add_position)
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: { sl_pct: 0.30, tp_pct: 0.60 }
    })
  end

  describe '.create_paper_tracker' do
    let(:ltp) { BigDecimal('150.50') }
    let(:quantity) { 75 }
    let(:side) { 'long_ce' }

    it 'creates a paper tracker with correct attributes' do
      tracker = described_class.create_paper_tracker(
        instrument: instrument,
        pick: pick,
        side: side,
        quantity: quantity,
        index_cfg: index_cfg,
        ltp: ltp
      )

      expect(tracker).to be_persisted
      expect(tracker.paper).to be true
      expect(tracker.status).to eq('active')
      expect(tracker.security_id).to eq(pick[:security_id])
      expect(tracker.symbol).to eq(pick[:symbol])
      expect(tracker.segment).to eq(pick[:segment])
      expect(tracker.side).to eq(side)
      expect(tracker.quantity).to eq(quantity)
      expect(tracker.entry_price).to eq(ltp)
      expect(tracker.avg_price).to eq(ltp)
    end

    it 'sets watchable to derivative when derivative_id is provided' do
      tracker = described_class.create_paper_tracker(
        instrument: instrument,
        pick: pick,
        side: side,
        quantity: quantity,
        index_cfg: index_cfg,
        ltp: ltp
      )

      expect(tracker.watchable).to eq(derivative)
      expect(tracker.instrument).to eq(instrument)
    end

    it 'sets watchable to instrument when no derivative_id' do
      pick_without_derivative = pick.except(:derivative_id)
      tracker = described_class.create_paper_tracker(
        instrument: instrument,
        pick: pick_without_derivative,
        side: side,
        quantity: quantity,
        index_cfg: index_cfg,
        ltp: ltp
      )

      expect(tracker.watchable).to eq(instrument)
      expect(tracker.instrument).to eq(instrument)
    end

    it 'initializes Redis PnL cache' do
      expect(Live::RedisPnlCache.instance).to receive(:store_pnl).with(
        hash_including(
          tracker_id: anything,
          pnl: BigDecimal(0),
          pnl_pct: 0.0,
          ltp: ltp
        )
      )

      described_class.create_paper_tracker(
        instrument: instrument,
        pick: pick,
        side: side,
        quantity: quantity,
        index_cfg: index_cfg,
        ltp: ltp
      )
    end

    it 'adds position to ActiveCache with default SL/TP' do
      expected_sl = (ltp.to_f * 0.70).round(2)
      expected_tp = (ltp.to_f * 1.60).round(2)

      expect(Positions::ActiveCache.instance).to receive(:add_position).with(
        tracker: anything,
        sl_price: expected_sl,
        tp_price: expected_tp
      )

      described_class.create_paper_tracker(
        instrument: instrument,
        pick: pick,
        side: side,
        quantity: quantity,
        index_cfg: index_cfg,
        ltp: ltp
      )
    end

    it 'sets correct metadata' do
      tracker = described_class.create_paper_tracker(
        instrument: instrument,
        pick: pick,
        side: side,
        quantity: quantity,
        index_cfg: index_cfg,
        ltp: ltp
      )

      expect(tracker.meta['index_key']).to eq('NIFTY')
      expect(tracker.meta['direction']).to eq(side)
      expect(tracker.meta['paper_trading']).to be true
      expect(tracker.meta['placed_at']).to be_present
    end

    it 'generates unique order number' do
      tracker1 = described_class.create_paper_tracker(
        instrument: instrument,
        pick: pick,
        side: side,
        quantity: quantity,
        index_cfg: index_cfg,
        ltp: ltp
      )

      sleep 0.01 # Ensure different timestamp

      tracker2 = described_class.create_paper_tracker(
        instrument: instrument,
        pick: pick,
        side: side,
        quantity: quantity,
        index_cfg: index_cfg,
        ltp: ltp
      )

      expect(tracker1.order_no).not_to eq(tracker2.order_no)
      expect(tracker1.order_no).to start_with('PAPER-')
    end

    context 'when validation fails' do
      it 'raises RecordInvalid error' do
        invalid_pick = pick.merge(security_id: nil)

        expect do
          described_class.create_paper_tracker(
            instrument: instrument,
            pick: invalid_pick,
            side: side,
            quantity: quantity,
            index_cfg: index_cfg,
            ltp: ltp
          )
        end.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe '.create_live_tracker' do
    let(:order_no) { 'ORD123456' }
    let(:ltp) { BigDecimal('200.75') }
    let(:quantity) { 50 }
    let(:side) { 'long_pe' }

    before do
      allow(PositionTracker).to receive(:build_or_average!).and_call_original
    end

    it 'creates a live tracker using PositionTracker.build_or_average!' do
      expect(PositionTracker).to receive(:build_or_average!).with(
        hash_including(
          watchable: anything,
          instrument: instrument,
          order_no: order_no,
          security_id: pick[:security_id],
          symbol: pick[:symbol],
          segment: pick[:segment],
          side: side,
          quantity: quantity,
          entry_price: ltp
        )
      )

      described_class.create_live_tracker(
        instrument: instrument,
        order_no: order_no,
        pick: pick,
        side: side,
        quantity: quantity,
        index_cfg: index_cfg,
        ltp: ltp
      )
    end

    it 'sets correct metadata' do
      tracker = described_class.create_live_tracker(
        instrument: instrument,
        order_no: order_no,
        pick: pick,
        side: side,
        quantity: quantity,
        index_cfg: index_cfg,
        ltp: ltp
      )

      expect(tracker.meta['index_key']).to eq('NIFTY')
      expect(tracker.meta['direction']).to eq(side)
      expect(tracker.meta['placed_at']).to be_present
    end

    context 'when averaging existing position' do
      let!(:existing_tracker) do
        create(:position_tracker,
               instrument: instrument,
               security_id: pick[:security_id],
               segment: pick[:segment],
               status: 'active',
               quantity: 25,
               entry_price: BigDecimal('180.00'))
      end

      it 'averages the position instead of creating new' do
        tracker = described_class.create_live_tracker(
          instrument: instrument,
          order_no: order_no,
          pick: pick,
          side: side,
          quantity: quantity,
          index_cfg: index_cfg,
          ltp: ltp
        )

        expect(tracker.id).to eq(existing_tracker.id)
        expect(tracker.quantity).to eq(75) # 25 + 50
        expect(tracker.entry_price).to be_within(0.01).of(BigDecimal('193.33')) # Weighted average
      end
    end
  end

  describe '.build_or_average' do
    let(:attributes) do
      {
        watchable: instrument,
        instrument: instrument,
        order_no: 'ORD789',
        security_id: '12345',
        symbol: 'TEST',
        segment: 'NSE_FNO',
        side: 'long_ce',
        quantity: 50,
        entry_price: BigDecimal('100.00'),
        meta: {}
      }
    end

    context 'when no active tracker exists' do
      it 'creates a new tracker' do
        expect do
          described_class.build_or_average(attributes)
        end.to change(PositionTracker, :count).by(1)

        tracker = PositionTracker.last
        expect(tracker.order_no).to eq('ORD789')
        expect(tracker.status).to eq('active')
      end
    end

    context 'when active tracker exists' do
      let!(:existing_tracker) do
        create(:position_tracker,
               instrument: instrument,
               security_id: '12345',
               segment: 'NSE_FNO',
               status: 'active',
               quantity: 25,
               entry_price: BigDecimal('90.00'))
      end

      it 'averages the position' do
        tracker = described_class.build_or_average(attributes)

        expect(tracker.id).to eq(existing_tracker.id)
        expect(tracker.quantity).to eq(75) # 25 + 50
        expect(tracker.entry_price).to be_within(0.01).of(BigDecimal('96.67')) # Weighted average
      end
    end
  end
end
