# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::BracketPlacer do
  let(:event_bus) { instance_double(Core::EventBus) }
  let(:active_cache) { instance_double(Positions::ActiveCache) }
  let(:bracket_placer) { described_class.new(event_bus: event_bus, active_cache: active_cache) }
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 123,
      order_no: 'ORD123',
      entry_price: BigDecimal('150.0'),
      active?: true,
      segment: 'NSE_FNO',
      security_id: '49081'
    )
  end

  before do
    allow(active_cache).to receive(:update_position).and_return(true)
    allow(event_bus).to receive(:publish)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe '#place_bracket' do
    context 'with provided SL/TP prices' do
      it 'places bracket with provided prices' do
        result = bracket_placer.place_bracket(
          tracker: tracker,
          sl_price: 105.0,
          tp_price: 240.0,
          reason: 'initial_bracket'
        )

        expect(result[:success]).to be true
        expect(result[:sl_price]).to eq(105.0)
        expect(result[:tp_price]).to eq(240.0)
      end

      it 'updates ActiveCache with SL/TP and peak_profit_pct' do
        bracket_placer.place_bracket(
          tracker: tracker,
          sl_price: 105.0,
          tp_price: 240.0
        )

        expect(active_cache).to have_received(:update_position).with(
          123,
          sl_price: 105.0,
          tp_price: 240.0,
          peak_profit_pct: 0.0
        )
      end
    end

    context 'without provided SL/TP prices (auto-calculate)' do
      it 'calculates SL as 30% below entry (entry * 0.70)' do
        result = bracket_placer.place_bracket(
          tracker: tracker,
          sl_price: nil,
          tp_price: nil
        )

        expect(result[:success]).to be true
        expect(result[:sl_price]).to eq(105.0) # 150.0 * 0.70
      end

      it 'calculates TP as 60% above entry (entry * 1.60)' do
        result = bracket_placer.place_bracket(
          tracker: tracker,
          sl_price: nil,
          tp_price: nil
        )

        expect(result[:success]).to be true
        expect(result[:tp_price]).to eq(240.0) # 150.0 * 1.60
      end

      it 'updates ActiveCache with calculated SL/TP and peak_profit_pct' do
        bracket_placer.place_bracket(
          tracker: tracker,
          sl_price: nil,
          tp_price: nil
        )

        expect(active_cache).to have_received(:update_position).with(
          123,
          sl_price: 105.0,
          tp_price: 240.0,
          peak_profit_pct: 0.0
        )
      end
    end

    context 'with partial prices (one provided, one calculated)' do
      it 'uses provided SL and calculates TP' do
        result = bracket_placer.place_bracket(
          tracker: tracker,
          sl_price: 100.0,
          tp_price: nil
        )

        expect(result[:success]).to be true
        expect(result[:sl_price]).to eq(100.0)
        expect(result[:tp_price]).to eq(240.0) # Calculated: 150.0 * 1.60
      end

      it 'calculates SL and uses provided TP' do
        result = bracket_placer.place_bracket(
          tracker: tracker,
          sl_price: nil,
          tp_price: 250.0
        )

        expect(result[:success]).to be true
        expect(result[:sl_price]).to eq(105.0) # Calculated: 150.0 * 0.70
        expect(result[:tp_price]).to eq(250.0)
      end
    end

    context 'with invalid tracker' do
      it 'returns failure if tracker is nil' do
        result = bracket_placer.place_bracket(
          tracker: nil,
          sl_price: 105.0,
          tp_price: 240.0
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Tracker not found')
      end

      it 'returns failure if tracker is not active' do
        inactive_tracker = instance_double(PositionTracker, active?: false)
        result = bracket_placer.place_bracket(
          tracker: inactive_tracker,
          sl_price: 105.0,
          tp_price: 240.0
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Tracker not active')
      end

      it 'returns failure if entry price is invalid' do
        invalid_tracker = instance_double(
          PositionTracker,
          id: 123,
          active?: true,
          entry_price: BigDecimal(0)
        )

        result = bracket_placer.place_bracket(
          tracker: invalid_tracker,
          sl_price: nil,
          tp_price: nil
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid entry price')
      end
    end

    context 'with invalid calculated prices' do
      it 'returns failure if calculated SL is not positive' do
        zero_entry_tracker = instance_double(
          PositionTracker,
          id: 123,
          active?: true,
          entry_price: BigDecimal(0),
          segment: 'NSE_FNO',
          security_id: '49081'
        )

        result = bracket_placer.place_bracket(
          tracker: zero_entry_tracker,
          sl_price: nil,
          tp_price: nil
        )

        expect(result[:success]).to be false
      end
    end

    context 'when emitting events' do
      it 'emits bracket_placed event' do
        bracket_placer.place_bracket(
          tracker: tracker,
          sl_price: 105.0,
          tp_price: 240.0,
          reason: 'initial_bracket'
        )

        expect(event_bus).to have_received(:publish) do |event, data|
          expect(data[:tracker_id]).to eq(123) if event == Core::EventBus::EVENTS[:bracket_placed]
        end
      end
    end

    context 'when tracking statistics' do
      it 'increments brackets_placed counter' do
        initial_stats = bracket_placer.stats
        bracket_placer.place_bracket(
          tracker: tracker,
          sl_price: 105.0,
          tp_price: 240.0
        )

        new_stats = bracket_placer.stats
        expect(new_stats[:brackets_placed]).to eq(initial_stats[:brackets_placed] + 1)
      end
    end
  end

  describe '#update_bracket' do
    let(:position_data) do
      instance_double(
        Positions::ActiveCache::PositionData,
        sl_price: 105.0,
        tp_price: 240.0
      )
    end

    before do
      allow(active_cache).to receive(:get_by_tracker_id).and_return(position_data)
    end

    it 'updates SL price' do
      result = bracket_placer.update_bracket(
        tracker: tracker,
        sl_price: 110.0
      )

      expect(result[:success]).to be true
      expect(result[:sl_price]).to eq(110.0)
    end

    it 'updates TP price' do
      result = bracket_placer.update_bracket(
        tracker: tracker,
        tp_price: 250.0
      )

      expect(result[:success]).to be true
      expect(result[:tp_price]).to eq(250.0)
    end

    it 'preserves existing values when not provided' do
      result = bracket_placer.update_bracket(
        tracker: tracker,
        sl_price: 110.0
      )

      expect(result[:success]).to be true
      expect(result[:sl_price]).to eq(110.0)
      expect(result[:tp_price]).to eq(240.0) # Preserved from position_data
    end
  end

  describe '#move_to_breakeven' do
    it 'moves SL to entry price' do
      allow(bracket_placer).to receive(:update_bracket).and_return(
        { success: true, sl_price: 150.0, tp_price: 240.0 }
      )

      result = bracket_placer.move_to_breakeven(tracker: tracker)

      expect(result[:success]).to be true
      expect(bracket_placer).to have_received(:update_bracket).with(
        tracker: tracker,
        sl_price: 150.0,
        reason: 'breakeven_lock'
      )
    end
  end

  describe '#move_to_trailing' do
    it 'moves SL to trailing price' do
      allow(bracket_placer).to receive(:update_bracket).and_return(
        { success: true, sl_price: 120.0, tp_price: 240.0 }
      )

      result = bracket_placer.move_to_trailing(tracker: tracker, trailing_price: 120.0)

      expect(result[:success]).to be true
      expect(bracket_placer).to have_received(:update_bracket).with(
        tracker: tracker,
        sl_price: 120.0,
        reason: 'trailing_stop'
      )
    end
  end

  describe '#stats' do
    it 'returns bracket statistics' do
      stats = bracket_placer.stats
      expect(stats).to include(
        brackets_placed: 0,
        brackets_modified: 0,
        brackets_failed: 0,
        sl_orders_placed: 0,
        tp_orders_placed: 0
      )
    end
  end
end
