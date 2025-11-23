# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::TrailingEngine do
  let(:active_cache) { instance_double(Positions::ActiveCache) }
  let(:bracket_placer) { instance_double(Orders::BracketPlacer) }
  let(:trailing_engine) { described_class.new(active_cache: active_cache, bracket_placer: bracket_placer) }
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 123,
      order_no: 'ORD123',
      active?: true
    )
  end

  let(:position_data) do
    instance_double(
      Positions::ActiveCache::PositionData,
      tracker_id: 123,
      entry_price: 150.0,
      current_ltp: 160.0,
      quantity: 75,
      sl_price: 105.0,
      tp_price: 240.0,
      pnl_pct: 6.67, # (160 - 150) / 150 * 100
      peak_profit_pct: 5.0,
      valid?: true
    )
  end

  before do
    allow(active_cache).to receive(:update_position).and_return(true)
    allow(bracket_placer).to receive(:update_bracket).and_return(
      { success: true, sl_price: 110.0, tp_price: 240.0 }
    )
    allow(PositionTracker).to receive(:find_by).and_return(tracker)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:debug)
  end

  describe '#process_tick' do
    context 'with valid position data' do
      it 'updates peak profit percentage if current exceeds peak' do
        result = trailing_engine.process_tick(position_data)

        expect(result[:peak_updated]).to be true
        expect(active_cache).to have_received(:update_position).with(
          123,
          peak_profit_pct: 6.67
        )
      end

      it 'applies tiered SL offsets based on profit percentage' do
        result = trailing_engine.process_tick(position_data)

        expect(result[:sl_updated]).to be true
        expect(result[:new_sl_price]).to be_a(Float)
      end

      it 'returns success result with all flags' do
        result = trailing_engine.process_tick(position_data)

        expect(result[:exit_triggered]).to be false
        expect(result[:error]).to be_nil
      end
    end

    context 'with peak drawdown check' do
      let(:exit_engine) { instance_double(Live::ExitEngine) }
      let(:high_peak_position) do
        instance_double(
          Positions::ActiveCache::PositionData,
          tracker_id: 123,
          entry_price: 150.0,
          current_ltp: 155.0,
          quantity: 75,
          sl_price: 105.0,
          tp_price: 240.0,
          pnl_pct: 3.33, # Current profit
          peak_profit_pct: 10.0, # Peak was 10%
          valid?: true
        )
      end

      before do
        allow(Positions::TrailingConfig).to receive(:peak_drawdown_triggered?).and_return(true)
        allow(exit_engine).to receive(:execute_exit).and_return(true)
      end

      it 'triggers exit if peak drawdown threshold is breached' do
        result = trailing_engine.process_tick(high_peak_position, exit_engine: exit_engine)

        expect(result[:exit_triggered]).to be true
        expect(result[:reason]).to eq('peak_drawdown_exit')
        expect(exit_engine).to have_received(:execute_exit)
      end

      it 'does not update SL if exit is triggered' do
        result = trailing_engine.process_tick(high_peak_position, exit_engine: exit_engine)

        expect(result[:sl_updated]).to be false
        expect(bracket_placer).not_to have_received(:update_bracket)
      end
    end

    context 'with invalid position data' do
      let(:invalid_position) do
        instance_double(
          Positions::ActiveCache::PositionData,
          valid?: false
        )
      end

      it 'returns failure result' do
        result = trailing_engine.process_tick(invalid_position)

        expect(result[:peak_updated]).to be false
        expect(result[:sl_updated]).to be false
        expect(result[:error]).to eq('Invalid position data')
      end
    end

    context 'when peak is not updated' do
      let(:lower_profit_position) do
        instance_double(
          Positions::ActiveCache::PositionData,
          tracker_id: 123,
          entry_price: 150.0,
          current_ltp: 155.0,
          quantity: 75,
          sl_price: 105.0,
          tp_price: 240.0,
          pnl_pct: 3.33, # Current profit
          peak_profit_pct: 5.0, # Peak is higher
          valid?: true
        )
      end

      it 'does not update peak if current < peak' do
        result = trailing_engine.process_tick(lower_profit_position)

        expect(result[:peak_updated]).to be false
        expect(active_cache).not_to have_received(:update_position).with(
          123,
          hash_including(peak_profit_pct: anything)
        )
      end
    end

    context 'when SL is not improved' do
      let(:position_with_high_sl) do
        instance_double(
          Positions::ActiveCache::PositionData,
          tracker_id: 123,
          entry_price: 150.0,
          current_ltp: 160.0,
          quantity: 75,
          sl_price: 120.0, # Already high SL
          tp_price: 240.0,
          pnl_pct: 6.67,
          peak_profit_pct: 5.0,
          valid?: true
        )
      end

      before do
        # Mock calculate_sl_price to return SL lower than current
        allow(Positions::TrailingConfig).to receive(:calculate_sl_price).and_return(110.0)
      end

      it 'does not update SL if new SL <= current SL' do
        result = trailing_engine.process_tick(position_with_high_sl)

        expect(result[:sl_updated]).to be false
        expect(result[:reason]).to eq('sl_not_improved')
        expect(bracket_placer).not_to have_received(:update_bracket)
      end
    end
  end

  describe '#check_peak_drawdown' do
    let(:exit_engine) { instance_double(Live::ExitEngine) }
    let(:position_with_drawdown) do
      instance_double(
        Positions::ActiveCache::PositionData,
        tracker_id: 123,
        peak_profit_pct: 10.0,
        pnl_pct: 4.0 # Drawdown = 6.0% (exceeds 5.0% threshold)
      )
    end

    before do
      allow(Positions::TrailingConfig).to receive(:peak_drawdown_triggered?).and_return(true)
      allow(exit_engine).to receive(:execute_exit).and_return(true)
    end

    it 'triggers exit if drawdown >= threshold' do
      result = trailing_engine.check_peak_drawdown(position_with_drawdown, exit_engine)

      expect(result).to be true
      expect(exit_engine).to have_received(:execute_exit)
    end

    it 'does not trigger exit if drawdown < threshold' do
      allow(Positions::TrailingConfig).to receive(:peak_drawdown_triggered?).and_return(false)

      result = trailing_engine.check_peak_drawdown(position_with_drawdown, exit_engine)

      expect(result).to be false
      expect(exit_engine).not_to have_received(:execute_exit)
    end

    it 'handles missing tracker gracefully' do
      allow(PositionTracker).to receive(:find_by).and_return(nil)

      result = trailing_engine.check_peak_drawdown(position_with_drawdown, exit_engine)

      expect(result).to be false
      expect(exit_engine).not_to have_received(:execute_exit)
    end
  end

  describe '#update_peak' do
    it 'updates peak if current > peak' do
      result = trailing_engine.update_peak(position_data)

      expect(result).to be true
      expect(active_cache).to have_received(:update_position).with(
        123,
        peak_profit_pct: 6.67
      )
    end

    it 'does not update peak if current <= peak' do
      lower_position = instance_double(
        Positions::ActiveCache::PositionData,
        tracker_id: 123,
        pnl_pct: 3.0,
        peak_profit_pct: 5.0
      )

      result = trailing_engine.update_peak(lower_position)

      expect(result).to be false
      expect(active_cache).not_to have_received(:update_position)
    end
  end

  describe '#apply_tiered_sl' do
    it 'calculates new SL based on profit percentage tier' do
      allow(Positions::TrailingConfig).to receive(:calculate_sl_price).with(150.0, 6.67).and_return(110.0)

      result = trailing_engine.apply_tiered_sl(position_data)

      expect(result[:updated]).to be true
      expect(result[:new_sl_price]).to eq(110.0)
    end

    it 'only updates SL if new SL > current SL' do
      allow(Positions::TrailingConfig).to receive(:calculate_sl_price).and_return(110.0)

      result = trailing_engine.apply_tiered_sl(position_data)

      expect(result[:updated]).to be true
      expect(bracket_placer).to have_received(:update_bracket).with(
        tracker: tracker,
        sl_price: 110.0,
        reason: /tiered_trailing/
      )
    end

    it 'does not update if new SL <= current SL' do
      allow(Positions::TrailingConfig).to receive(:calculate_sl_price).and_return(100.0) # Lower than current 105.0

      result = trailing_engine.apply_tiered_sl(position_data)

      expect(result[:updated]).to be false
      expect(result[:reason]).to eq('sl_not_improved')
    end

    it 'handles invalid position data' do
      invalid_position = instance_double(
        Positions::ActiveCache::PositionData,
        valid?: false
      )

      result = trailing_engine.apply_tiered_sl(invalid_position)

      expect(result[:updated]).to be false
      expect(result[:reason]).to eq('invalid_position')
    end
  end
end
