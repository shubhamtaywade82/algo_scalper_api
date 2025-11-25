# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::TrailingEngine do
  let(:active_cache) { instance_double(Positions::ActiveCache, update_position: true) }
  let(:bracket_placer) { instance_double(Orders::BracketPlacer) }
  let(:exit_engine) { instance_double(Live::ExitEngine) }
  let(:tracker) { instance_double(PositionTracker, id: 42, order_no: 'ORD42', active?: true) }
  let(:engine) { described_class.new(active_cache: active_cache, bracket_placer: bracket_placer) }

  before do
    allow(PositionTracker).to receive(:find_by).and_return(tracker)
    allow(bracket_placer).to receive(:update_bracket).and_return({ success: true })
    allow(exit_engine).to receive(:execute_exit)
    allow(Rails.logger).to receive_messages(info: nil, warn: nil, error: nil, debug: nil)
  end

  describe '#process_tick' do
    it 'updates peak and SL when tier threshold is satisfied' do
      position = build_position(pnl_pct: 12.0, peak_profit_pct: 10.0, sl_price: 70.0)

      result = engine.process_tick(position, exit_engine: nil)

      expect(result[:peak_updated]).to be true
      expect(result[:sl_updated]).to be true
      expect(result[:exit_triggered]).to be false
      expect(active_cache).to have_received(:update_position).with(
        position.tracker_id,
        hash_including(sl_price: be > 70.0, sl_offset_pct: -5.0)
      )
    end

    it 'skips SL update when profit has not reached the first tier' do
      position = build_position(pnl_pct: 3.0, peak_profit_pct: 5.0)

      result = engine.process_tick(position)

      expect(result[:sl_updated]).to be false
      expect(result[:reason]).to eq('tier_not_reached')
      expect(bracket_placer).not_to have_received(:update_bracket)
    end

    it 'returns failure for invalid position data' do
      position = build_position(current_ltp: nil)

      result = engine.process_tick(position)

      expect(result[:error]).to eq('Invalid position data')
    end
  end

  describe '#check_peak_drawdown' do
    context 'when activation flag is disabled' do
      before do
        allow(engine).to receive(:feature_flags).and_return(enable_peak_drawdown_activation: false)
      end

      it 'exits immediately when drawdown threshold is met' do
        position = build_position(peak_profit_pct: 40.0, pnl_pct: 34.0, sl_offset_pct: 12.0)

        result = engine.process_tick(position, exit_engine: exit_engine)

        expect(result[:exit_triggered]).to be true
        expect(exit_engine).to have_received(:execute_exit).once
      end
    end

    context 'when activation flag is enabled' do
      before do
        allow(engine).to receive(:feature_flags).and_return(enable_peak_drawdown_activation: true)
      end

      it 'does not exit if activation thresholds are not met' do
        position = build_position(peak_profit_pct: 40.0, pnl_pct: 22.0, sl_offset_pct: 8.0)

        result = engine.process_tick(position, exit_engine: exit_engine)

        expect(result[:exit_triggered]).to be false
        expect(exit_engine).not_to have_received(:execute_exit)
      end

      it 'exits once when activation thresholds are satisfied' do
        position = build_position(peak_profit_pct: 60.0, pnl_pct: 30.0, sl_offset_pct: 12.0)
        allow(tracker).to receive(:active?).and_return(true, false)

        result_first = engine.process_tick(position, exit_engine: exit_engine)
        result_second = engine.process_tick(position, exit_engine: exit_engine)

        expect(result_first[:exit_triggered]).to be true
        expect(result_second[:exit_triggered]).to be false
        expect(exit_engine).to have_received(:execute_exit).once
      end
    end
  end

  def build_position(overrides = {})
    defaults = {
      tracker_id: 42,
      security_id: 'SEC42',
      segment: 'NSE_FNO',
      entry_price: 100.0,
      quantity: 50,
      sl_price: 70.0,
      tp_price: 150.0,
      high_water_mark: 0.0,
      current_ltp: 110.0,
      pnl_pct: 10.0,
      peak_profit_pct: 12.0,
      sl_offset_pct: nil,
      pnl: 0.0,
      trend: :neutral,
      time_in_position: 60,
      breakeven_locked: false,
      trailing_stop_price: nil,
      last_updated_at: Time.current
    }

    Positions::ActiveCache::PositionData.new(defaults.merge(overrides))
  end
end
