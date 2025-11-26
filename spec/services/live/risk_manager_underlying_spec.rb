# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService, '#process_trailing_for_all_positions' do
  subject(:service) { described_class.new(exit_engine: exit_engine) }

  let(:exit_engine) { instance_double(Live::ExitEngine) }
  let(:active_cache) { instance_double(Positions::ActiveCache) }
  let(:trailing_engine) { instance_double(Live::TrailingEngine, process_tick: { exit_triggered: false }) }
  let(:bracket_placer) { instance_double(Orders::BracketPlacer) }
  let(:watchable) { create(:derivative, :nifty_call_option, security_id: '50001') }
  let(:tracker) do
    create(
      :position_tracker,
      :option_position,
      watchable: watchable,
      instrument: watchable.instrument,
      segment: 'NSE_FNO',
      security_id: watchable.security_id,
      entry_price: 100.0,
      quantity: 25,
      status: :active,
      meta: { 'index_key' => 'NIFTY', 'direction' => 'bullish' }
    )
  end
  let(:position_data) do
    Positions::ActiveCache::PositionData.new(
      tracker_id: tracker.id,
      security_id: tracker.security_id,
      segment: tracker.segment,
      entry_price: tracker.entry_price,
      quantity: tracker.quantity,
      sl_price: 90.0,
      tp_price: 150.0,
      high_water_mark: 10_000,
      current_ltp: 140.0,
      pnl_pct: 40.0,
      peak_profit_pct: 45.0,
      sl_offset_pct: 12.0,
      position_direction: :bullish,
      index_key: 'NIFTY',
      underlying_segment: 'IDX_I',
      underlying_security_id: '13',
      underlying_symbol: 'NIFTY',
      last_updated_at: Time.current
    )
  end
  let(:redis_tick_cache) { instance_double(Live::RedisTickCache, fetch_tick: nil) }

  before do
    allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
    allow(active_cache).to receive(:all_positions).and_return([position_data])
    allow(active_cache).to receive(:update_position).and_return(true)
    allow(Live::TickCache).to receive(:ltp).and_return(position_data.current_ltp)
    allow(Live::RedisTickCache).to receive(:instance).and_return(redis_tick_cache)
    allow(exit_engine).to receive(:execute_exit)
    allow(tracker).to receive(:with_lock).and_yield
    allow(tracker).to receive(:exited?).and_return(false)
    service.instance_variable_set(:@trailing_engine, trailing_engine)
    service.instance_variable_set(:@bracket_placer, bracket_placer)
  end

  describe 'underlying exits' do
    before do
      stub_algo_config(underlying_enabled: true, peak_enabled: false)
      allow(service).to receive(:trackers_for_positions).and_return({ tracker.id => tracker })
      allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(underlying_state)
    end

    let(:underlying_state) do
      OpenStruct.new(
        trend_score: 15,
        bos_state: :broken,
        bos_direction: :bearish,
        atr_trend: :flat,
        atr_ratio: 1.0,
        mtf_confirm: true
      )
    end

    it 'exits immediately on structure break against position' do
      expect(exit_engine).to receive(:execute_exit).with(tracker, 'underlying_structure_break').once

      service.send(:process_trailing_for_all_positions)

      expect(trailing_engine).not_to have_received(:process_tick)
    end

    it 'exits when trend score drops below threshold' do
      underlying_state.trend_score = 5
      underlying_state.bos_state = :intact
      expect(exit_engine).to receive(:execute_exit).with(tracker, 'underlying_trend_weak').once

      service.send(:process_trailing_for_all_positions)
    end
  end

  describe 'peak drawdown gating' do
    before do
      stub_algo_config(underlying_enabled: false, peak_enabled: true,
                       risk_overrides: {
                         peak_drawdown_activation_profit_pct: 30.0,
                         peak_drawdown_activation_sl_offset_pct: 10.0
                       })
      allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(nil)
      allow(service).to receive(:trackers_for_positions).and_return({ tracker.id => tracker })
    end

    it 'exits when drawdown breaches threshold and gating active' do
      position_data.peak_profit_pct = 40.0
      position_data.pnl_pct = 32.0
      expect(exit_engine).to receive(:execute_exit).with(tracker, 'peak_drawdown_exit (drawdown: 8.00%)').once

      service.send(:process_trailing_for_all_positions)
    end

    it 'does not exit when gating conditions are not met (profit < activation threshold)' do
      position_data.peak_profit_pct = 20.0
      position_data.pnl_pct = 14.0
      position_data.sl_offset_pct = 5.0

      service.send(:process_trailing_for_all_positions)

      expect(exit_engine).not_to have_received(:execute_exit)
      expect(trailing_engine).to have_received(:process_tick).once
    end

    it 'does not exit when gating conditions are not met (sl_offset < activation threshold)' do
      position_data.peak_profit_pct = 35.0
      position_data.pnl_pct = 30.0
      position_data.sl_offset_pct = 8.0 # Below 10.0 threshold

      service.send(:process_trailing_for_all_positions)

      expect(exit_engine).not_to have_received(:execute_exit)
      expect(trailing_engine).to have_received(:process_tick).once
    end

    it 'exits when both activation thresholds are met and drawdown exceeds limit' do
      position_data.peak_profit_pct = 35.0
      position_data.pnl_pct = 28.0 # 7% drawdown from 35% peak
      position_data.sl_offset_pct = 12.0 # Above 10.0 threshold

      expect(exit_engine).to receive(:execute_exit).with(
        tracker,
        match(/peak_drawdown_exit.*drawdown.*7/)
      ).once

      service.send(:process_trailing_for_all_positions)
    end
  end

  describe 'idempotent exits' do
    before do
      stub_algo_config(underlying_enabled: true, peak_enabled: true,
                       risk_overrides: {
                         peak_drawdown_activation_profit_pct: 20.0,
                         peak_drawdown_activation_sl_offset_pct: 5.0
                       })
      allow(service).to receive(:trackers_for_positions).and_return({ tracker.id => tracker })
      position_data.peak_profit_pct = 30.0
      position_data.pnl_pct = 20.0
      allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(
        OpenStruct.new(
          trend_score: 8,
          bos_state: :broken,
          bos_direction: :bearish,
          atr_trend: :falling,
          atr_ratio: 0.5,
          mtf_confirm: false
        )
      )
    end

    it 'triggers only one exit when multiple conditions fire' do
      expect(exit_engine).to receive(:execute_exit).once

      service.send(:process_trailing_for_all_positions)
    end
  end

  def stub_algo_config(underlying_enabled:, peak_enabled:, risk_overrides: {})
    feature_flags = {
      enable_direction_before_chain: false,
      enable_auto_subscribe_unsubscribe: false,
      enable_demand_driven_services: false,
      enable_underlying_aware_exits: underlying_enabled,
      enable_peak_drawdown_activation: peak_enabled
    }

    risk = {
      sl_pct: 0.1,
      tp_pct: 0.2,
      exit_drop_pct: 0.03,
      underlying_trend_score_threshold: 12,
      underlying_atr_collapse_multiplier: 0.7,
      peak_drawdown_activation_profit_pct: 25.0,
      peak_drawdown_activation_sl_offset_pct: 10.0
    }.merge(risk_overrides)

    config = {
      feature_flags: feature_flags,
      risk: risk,
      indices: [{ key: 'NIFTY', segment: 'IDX_I', sid: '13' }],
      signals: { primary_timeframe: '1m', confirmation_timeframe: '5m' },
      paper_trading: { enabled: true }
    }
    allow(AlgoConfig).to receive(:fetch).and_return(config)
  end
end
