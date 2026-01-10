# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::EntryManager do
  let(:daily_limits) { instance_double(Live::DailyLimits) }
  let(:event_bus) { instance_double(Core::EventBus) }
  let(:active_cache) { instance_double(Positions::ActiveCache) }
  let(:entry_manager) { described_class.new(event_bus: event_bus, active_cache: active_cache) }
  let(:index_cfg) { { key: 'NIFTY', segment: 'NSE_INDEX', sid: '26000' } }
  let(:pick) do
    {
      security_id: '49081',
      segment: 'NSE_FNO',
      symbol: 'NIFTY-25Jan2024-25000-CE',
      lot_size: 75,
      ltp: 150.5
    }
  end
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 123,
      order_no: 'ORD123',
      entry_price: BigDecimal('150.5'),
      quantity: 75,
      segment: 'NSE_FNO',
      security_id: '49081',
      symbol: 'NIFTY-25Jan2024-25000-CE',
      active?: true
    )
  end
  let(:position_data) { instance_double(Positions::ActiveCache::PositionData) }

  before do
    allow(Live::DailyLimits).to receive(:new).and_return(daily_limits)
    allow(daily_limits).to receive(:record_trade).and_return(true)
    allow(Entries::EntryGuard).to receive(:try_enter).and_return(true)
    allow(entry_manager).to receive(:find_tracker_for_pick).and_return(tracker)
    allow(active_cache).to receive(:add_position).and_return(position_data)
    allow(event_bus).to receive(:publish)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe '#process_entry' do
    context 'with valid entry' do
      let(:bracket_placer) { instance_double(Orders::BracketPlacer) }

      before do
        allow(Orders::BracketPlacer).to receive(:new).and_return(bracket_placer)
        allow(bracket_placer).to receive(:place_bracket).and_return(
          { success: true, sl_price: 105.35, tp_price: 240.8 }
        )
      end

      it 'processes entry successfully' do
        result = entry_manager.process_entry(
          signal_result: { candidate: pick },
          index_cfg: index_cfg,
          direction: :bullish
        )

        expect(result[:success]).to be true
        expect(result[:tracker]).to eq(tracker)
        expect(result[:sl_price]).to eq(105.35)
        expect(result[:tp_price]).to eq(240.8)
      end

      it 'calls BracketPlacer.place_bracket' do
        entry_manager.process_entry(
          signal_result: { candidate: pick },
          index_cfg: index_cfg,
          direction: :bullish
        )

        expect(bracket_placer).to have_received(:place_bracket).with(
          tracker: tracker,
          sl_price: 105.35,
          tp_price: 240.8,
          reason: 'initial_bracket'
        )
      end

      it 'adds position to ActiveCache' do
        entry_manager.process_entry(
          signal_result: { candidate: pick },
          index_cfg: index_cfg,
          direction: :bullish
        )

        expect(active_cache).to have_received(:add_position).with(
          tracker: tracker,
          sl_price: 105.35,
          tp_price: 240.8
        )
      end
    end

    context 'with trend_score' do
      let(:risk_allocator) { instance_double(Capital::DynamicRiskAllocator) }
      let(:bracket_placer) { instance_double(Orders::BracketPlacer) }

      before do
        allow(Capital::DynamicRiskAllocator).to receive(:new).and_return(risk_allocator)
        allow(risk_allocator).to receive(:risk_pct_for).and_return(0.035)
        allow(Orders::BracketPlacer).to receive(:new).and_return(bracket_placer)
        allow(bracket_placer).to receive(:place_bracket).and_return(
          { success: true, sl_price: 105.35, tp_price: 240.8 }
        )
      end

      it 'calculates dynamic risk percentage' do
        entry_manager.process_entry(
          signal_result: { candidate: pick },
          index_cfg: index_cfg,
          direction: :bullish,
          trend_score: 15.0
        )

        expect(risk_allocator).to have_received(:risk_pct_for).with(
          index_key: 'NIFTY',
          trend_score: 15.0
        )
      end

      it 'includes risk_pct in result' do
        result = entry_manager.process_entry(
          signal_result: { candidate: pick },
          index_cfg: index_cfg,
          direction: :bullish,
          trend_score: 15.0
        )

        expect(result[:risk_pct]).to eq(0.035)
      end

      it 'includes risk_pct in entry_filled event' do
        entry_manager.process_entry(
          signal_result: { candidate: pick },
          index_cfg: index_cfg,
          direction: :bullish,
          trend_score: 15.0
        )

        expect(event_bus).to have_received(:publish) do |event, data|
          expect(data[:risk_pct]).to eq(0.035) if event == Core::EventBus::EVENTS[:entry_filled]
        end
      end
    end

    context 'with quantity < 1 lot' do
      let(:small_tracker) do
        instance_double(
          PositionTracker,
          id: 123,
          order_no: 'ORD123',
          entry_price: BigDecimal('150.5'),
          quantity: 50, # Less than lot_size (75)
          segment: 'NSE_FNO',
          security_id: '49081',
          symbol: 'NIFTY-25Jan2024-25000-CE',
          active?: true
        )
      end

      before do
        allow(entry_manager).to receive(:find_tracker_for_pick).and_return(small_tracker)
      end

      it 'rejects entry with quantity < 1 lot' do
        result = entry_manager.process_entry(
          signal_result: { candidate: pick },
          index_cfg: index_cfg,
          direction: :bullish
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Quantity 50 < 1 lot (75)')
      end
    end

    context 'when EntryGuard validation fails' do
      before do
        allow(Entries::EntryGuard).to receive(:try_enter).and_return(false)
      end

      it 'returns failure result' do
        result = entry_manager.process_entry(
          signal_result: { candidate: pick },
          index_cfg: index_cfg,
          direction: :bullish
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Entry validation failed')
      end
    end

    context 'when tracker not found' do
      before do
        allow(entry_manager).to receive(:find_tracker_for_pick).and_return(nil)
      end

      it 'returns failure result' do
        result = entry_manager.process_entry(
          signal_result: { candidate: pick },
          index_cfg: index_cfg,
          direction: :bullish
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('PositionTracker not found after entry')
      end
    end

    context 'when bracket placement fails' do
      let(:bracket_placer) { instance_double(Orders::BracketPlacer) }

      before do
        allow(Orders::BracketPlacer).to receive(:new).and_return(bracket_placer)
        allow(bracket_placer).to receive(:place_bracket).and_return(
          { success: false, error: 'Bracket placement failed' }
        )
      end

      it 'logs warning but continues' do
        result = entry_manager.process_entry(
          signal_result: { candidate: pick },
          index_cfg: index_cfg,
          direction: :bullish
        )

        expect(result[:success]).to be true
        expect(result[:bracket_result][:success]).to be false
        expect(Rails.logger).to have_received(:warn).with(
          /Bracket placement failed/
        )
      end
    end

    context 'with bearish direction (PE)' do
      let(:bracket_placer) { instance_double(Orders::BracketPlacer) }

      before do
        allow(Orders::BracketPlacer).to receive(:new).and_return(bracket_placer)
        allow(bracket_placer).to receive(:place_bracket).and_return(
          { success: true, sl_price: 195.65, tp_price: 75.25 }
        )
      end

      it 'calculates SL/TP for bearish positions' do
        result = entry_manager.process_entry(
          signal_result: { candidate: pick },
          index_cfg: index_cfg,
          direction: :bearish
        )

        expect(result[:success]).to be true
        # For bearish: SL = entry * 1.30, TP = entry * 0.50
        expect(result[:sl_price]).to eq(195.65) # 150.5 * 1.30
        expect(result[:tp_price]).to eq(75.25)  # 150.5 * 0.50
      end
    end
  end

  describe '#stats' do
    it 'returns entry statistics' do
      stats = entry_manager.stats
      expect(stats).to include(
        entries_attempted: 0,
        entries_successful: 0,
        entries_failed: 0,
        validation_failures: 0,
        allocation_failures: 0
      )
    end
  end
end
