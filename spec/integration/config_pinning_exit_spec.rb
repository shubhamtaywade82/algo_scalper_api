# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Config pinning on exit path' do
  before do
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config, nil)
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config_expires_at, nil)
  end

  describe 'percentage_pnl_exit_hit?' do
    let(:tracker) do
      instance_double(
        PositionTracker,
        meta: {
          'config_snapshot' => {
            'risk' => {
              'percentage_pnl_exit' => { 'enabled' => true, 'target_pct' => 0.10 }
            }
          }
        },
        entry_price: 100.0,
        quantity: 1
      )
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: { percentage_pnl_exit: { enabled: true, target_pct: 0.99 } },
        exit: { trailing: { enabled: false } }
      )
    end

    it 'uses pinned target_pct when live config differs' do
      snapshot = { pnl_pct: 0.15, hwm_pnl: 0.0 }

      expect(Live::UnifiedExitChecker.percentage_pnl_exit_hit?(tracker, snapshot)).to be(true)
    end

    it 'does not fire when pnl is below pinned target' do
      snapshot = { pnl_pct: 0.05, hwm_pnl: 0.0 }

      expect(Live::UnifiedExitChecker.percentage_pnl_exit_hit?(tracker, snapshot)).to be(false)
    end
  end

  describe 'emergency_peak_loss_exit_triggered?' do
    let(:tracker) do
      instance_double(
        PositionTracker,
        meta: {
          'config_snapshot' => {
            'position_sizing' => {
              'drawdown' => {
                'emergency_peak_loss_exit' => true,
                'emergency_min_peak_pct' => 0.20
              }
            }
          }
        },
        entry_price: 100.0,
        quantity: 10,
        high_water_mark_pnl: 250.0
      )
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        position_sizing: {
          drawdown: {
            emergency_peak_loss_exit: true,
            emergency_min_peak_pct: 0.99
          }
        }
      )
    end

    it 'uses pinned emergency_min_peak_pct when live config differs' do
      allow(tracker).to receive(:current_pnl_pct).and_return(-0.03)

      expect(Live::UnifiedExitChecker.emergency_peak_loss_exit_triggered?(tracker)).to be(true)
    end

    it 'does not fire when peak profit is below pinned threshold' do
      allow(tracker).to receive_messages(high_water_mark_pnl: 50.0, current_pnl_pct: -0.03)

      expect(Live::UnifiedExitChecker.emergency_peak_loss_exit_triggered?(tracker)).to be(false)
    end
  end

  describe 'loss_limit_hit?' do
    let(:tracker) do
      instance_double(
        PositionTracker,
        meta: {
          'config_snapshot' => {
            'risk' => { 'sl_pct' => 0.08 },
            'exit' => { 'stop_loss' => { 'type' => 'static', 'value' => 0.08 } }
          }
        },
        instrument: nil,
        watchable: nil
      )
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: { sl_pct: 0.50 },
        exit: { stop_loss: { type: 'static', value: 0.50 } }
      )
    end

    it 'uses pinned stop loss when live config differs' do
      snapshot = { pnl_pct: -0.09 }

      expect(Live::UnifiedExitChecker.loss_limit_hit?(tracker, snapshot)).to be(true)
    end

    it 'does not fire when loss is below pinned stop' do
      snapshot = { pnl_pct: -0.05 }

      expect(Live::UnifiedExitChecker.loss_limit_hit?(tracker, snapshot)).to be(false)
    end
  end

  describe 'profit_target_hit?' do
    let(:tracker) do
      instance_double(
        PositionTracker,
        meta: {
          'config_snapshot' => {
            'exit' => { 'take_profit' => 0.20, 'trailing' => { 'enabled' => false } },
            'risk' => {}
          }
        },
        entry_price: 100.0,
        quantity: 1
      )
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        exit: { take_profit: 0.99, trailing: { enabled: false } },
        risk: {}
      )
    end

    it 'uses pinned take profit when live config differs' do
      snapshot = { pnl_pct: 0.25, hwm_pnl: 0.0 }

      expect(Live::UnifiedExitChecker.profit_target_hit?(tracker, snapshot)).to be(true)
    end

    it 'does not fire when pnl is below pinned take profit' do
      snapshot = { pnl_pct: 0.15, hwm_pnl: 0.0 }

      expect(Live::UnifiedExitChecker.profit_target_hit?(tracker, snapshot)).to be(false)
    end
  end
end
