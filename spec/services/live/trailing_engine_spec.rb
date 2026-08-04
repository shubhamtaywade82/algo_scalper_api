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
    allow(tracker).to receive(:update_column)
    allow(tracker).to receive(:runtime_meta_fetch).and_return(nil)
    allow(tracker).to receive(:with_lock).and_yield
    allow(tracker).to receive(:exited?).and_return(false)
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
        # peak 0.20, current 0.12, sl_offset 0.08
        # OR logic: profit 0.20 >= 0.25 (False) OR sl_offset 0.08 >= 0.10 (False) → blocked
        position = build_position(peak_profit_pct: 0.20, pnl_pct: 0.12, sl_offset_pct: 0.08)

        result = engine.process_tick(position, exit_engine: exit_engine)

        expect(result[:exit_triggered]).to be false
        expect(exit_engine).not_to have_received(:execute_exit)
      end

      it 'exits once when activation thresholds are satisfied' do
        # peak 0.60, current 0.30
        # sl_price 112.0 means sl_offset is 0.12 (12%)
        # activation thresholds: peak >= 0.25 OR sl_offset >= 0.10 (True)
        # drawdown 0.30 >= threshold 0.008 (True)
        position = build_position(peak_profit_pct: 0.60, pnl_pct: 0.30, sl_price: 112.0, sl_offset_pct: 0.12)
        allow(tracker).to receive(:active?).and_return(true, false)

        result_first = engine.process_tick(position, exit_engine: exit_engine)
        result_second = engine.process_tick(position, exit_engine: exit_engine)

        expect(result_first[:exit_triggered]).to be true
        expect(result_second[:exit_triggered]).to be false
        expect(exit_engine).to have_received(:execute_exit).once
      end
    end

    it 'passes capital deployed to TrailingConfig' do
      # Entry 100 * Qty 50 = 5000 capital
      position = build_position(entry_price: 100.0, quantity: 50, peak_profit_pct: 0.10, pnl_pct: 0.05)

      expect(trailing_view).to receive(:peak_drawdown_triggered?).with(
        0.10, 0.05, hash_including(_capital_deployed: 5000.0)
      ).and_return(false)

      engine.check_peak_drawdown(position, exit_engine)
    end
  end

  describe '#check_peak_drawdown emergency exit' do
    it 'triggers emergency exit when peak >= 10% and current < -2%' do
      allow(tracker).to receive(:meta).and_return(
        'config_snapshot' => {
          'position_sizing' => {
            'drawdown' => { 'emergency_peak_loss_exit' => true, 'emergency_min_peak_pct' => 0.10 }
          }
        }
      )
      allow(engine).to receive(:feature_flags).and_return(enable_peak_drawdown_activation: false)
      position = build_position(peak_profit_pct: 0.15, pnl_pct: -0.05)
      allow(Live::ExitEngine).to receive(:execute_exit)

      result = engine.check_peak_drawdown(position, exit_engine)
      expect(result).to be true
      expect(Live::ExitEngine).to have_received(:execute_exit).with(
        hash_including(reason: /emergency_peak_loss_exit/)
      )
    end

    it 'does not trigger emergency when peak < 10%' do
      allow(tracker).to receive(:meta).and_return(
        'config_snapshot' => {
          'position_sizing' => {
            'drawdown' => { 'emergency_peak_loss_exit' => true, 'emergency_min_peak_pct' => 0.10 }
          }
        }
      )
      allow(engine).to receive(:feature_flags).and_return(enable_peak_drawdown_activation: false)
      allow(Live::ExitEngine).to receive(:execute_exit)
      position = build_position(peak_profit_pct: 0.05, pnl_pct: -0.05)

      engine.check_peak_drawdown(position, exit_engine)
      expect(Live::ExitEngine).not_to have_received(:execute_exit)
    end

    it 'does not trigger emergency when current loss is shallow (> -2%)' do
      allow(tracker).to receive(:meta).and_return(
        'config_snapshot' => {
          'position_sizing' => {
            'drawdown' => { 'emergency_peak_loss_exit' => true, 'emergency_min_peak_pct' => 0.10 }
          }
        }
      )
      allow(engine).to receive(:feature_flags).and_return(enable_peak_drawdown_activation: false)
      allow(Live::ExitEngine).to receive(:execute_exit)
      position = build_position(peak_profit_pct: 0.15, pnl_pct: -0.01)

      engine.check_peak_drawdown(position, exit_engine)
      expect(Live::ExitEngine).not_to have_received(:execute_exit)
    end
  end

  describe '#update_peak persistence' do
    it 'persists extremes to Redis when new peak is reached' do
      runtime_cache = Live::PositionRuntimeCache.instance
      allow(runtime_cache).to receive(:merge).and_call_original

      position = build_position(entry_price: 100.0, peak_profit_pct: 0.10, pnl_pct: 0.20)

      expect(tracker).not_to receive(:update_column)

      engine.update_peak(position, tracker: tracker)

      expect(runtime_cache).to have_received(:merge).with(
        tracker.id,
        hash_including(highest_price: 120.0, lowest_price: kind_of(Numeric))
      )
    end
  end

  describe '#check_peak_drawdown emergency exit' do
    it 'triggers emergency exit when peak >= 10% and current < -2%' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        position_sizing: {
          drawdown: { emergency_peak_loss_exit: true, emergency_min_peak_pct: 0.10 }
        },
        feature_flags: { enable_peak_drawdown_activation: false }
      })
      position = build_position(peak_profit_pct: 0.15, pnl_pct: -0.05)
      allow(Live::ExitEngine).to receive(:execute_exit)

      result = engine.check_peak_drawdown(position, exit_engine)
      expect(result).to be true
      expect(Live::ExitEngine).to have_received(:execute_exit).with(
        hash_including(reason: /emergency_peak_loss_exit/)
      )
    end

    it 'does not trigger emergency when peak < 10%' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        position_sizing: {
          drawdown: { emergency_peak_loss_exit: true, emergency_min_peak_pct: 0.10 }
        },
        feature_flags: { enable_peak_drawdown_activation: false }
      })
      allow(Live::ExitEngine).to receive(:execute_exit)
      position = build_position(peak_profit_pct: 0.05, pnl_pct: -0.05)

      result = engine.check_peak_drawdown(position, exit_engine)
      expect(Live::ExitEngine).not_to have_received(:execute_exit)
    end

    it 'does not trigger emergency when current loss is shallow (> -2%)' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        position_sizing: {
          drawdown: { emergency_peak_loss_exit: true, emergency_min_peak_pct: 0.10 }
        },
        feature_flags: { enable_peak_drawdown_activation: false }
      })
      allow(Live::ExitEngine).to receive(:execute_exit)
      position = build_position(peak_profit_pct: 0.15, pnl_pct: -0.01)

      result = engine.check_peak_drawdown(position, exit_engine)
      expect(Live::ExitEngine).not_to have_received(:execute_exit)
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
