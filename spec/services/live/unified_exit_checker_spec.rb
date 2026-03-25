# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::UnifiedExitChecker do
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 1,
      active?: true,
      entry_price: 200.0,
      quantity: 50,
      high_water_mark_pnl: 0.0,
      current_pnl_pct: 0.0,
      meta: {},
      order_no: 'ORD-1'
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      position_sizing: {
        drawdown: {
          emergency_peak_loss_exit: true,
          emergency_min_peak_pct: 0.10
        }
      },
      risk: {},
      indices: [{ key: 'NIFTY', segment: 'IDX_I', sid: '13' }]
    })
  end

  describe 'emergency peak-loss exit' do
    it 'triggers when peak >= 10% and current < -2%' do
      allow(tracker).to receive_messages(high_water_mark_pnl: 1500.0, current_pnl_pct: -0.05)      # -5%

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be true
    end

    it 'does not trigger when peak < 10%' do
      allow(tracker).to receive_messages(high_water_mark_pnl: 500.0, current_pnl_pct: -0.05)

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end

    it 'does not trigger when current loss is shallow (> -2%)' do
      allow(tracker).to receive_messages(high_water_mark_pnl: 1500.0, current_pnl_pct: -0.01)      # -1% (above -2% threshold)

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end

    it 'does not trigger when disabled in config' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        position_sizing: {
          drawdown: { emergency_peak_loss_exit: false }
        },
        risk: {},
        indices: []
      })
      allow(tracker).to receive_messages(high_water_mark_pnl: 1500.0, current_pnl_pct: -0.05)

      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end

    it 'handles zero entry value gracefully' do
      allow(tracker).to receive(:entry_price).and_return(0.0)
      result = described_class.send(:emergency_peak_loss_exit_triggered?, tracker)
      expect(result).to be false
    end
  end

  describe 'structure invalidation' do
    it 'triggers exit for long_pe when underlying rises above invalidation price' do
      allow(tracker).to receive(:meta).and_return({
        'direction' => 'long_pe',
        'structure_invalidation_price' => 23_800.0,
        'index_key' => 'NIFTY'
      })
      tick = double(ltp: 23_850.0)
      allow(Live::TickQuery).to receive(:for_security).and_return(tick)

      result = described_class.send(:structure_invalidated?, tracker, 23_850.0, 23_800.0)
      expect(result).to be true
    end

    it 'triggers exit for long_ce when underlying falls below invalidation price' do
      allow(tracker).to receive(:meta).and_return({
        'direction' => 'long_ce',
        'structure_invalidation_price' => 23_800.0,
        'index_key' => 'NIFTY'
      })

      result = described_class.send(:structure_invalidated?, tracker, 23_750.0, 23_800.0)
      expect(result).to be true
    end

    it 'does not trigger for long_pe when underlying is below invalidation' do
      allow(tracker).to receive(:meta).and_return({ 'direction' => 'long_pe' })
      result = described_class.send(:structure_invalidated?, tracker, 23_750.0, 23_800.0)
      expect(result).to be false
    end

    it 'does not trigger for unknown direction' do
      allow(tracker).to receive(:meta).and_return({ 'direction' => 'unknown' })
      result = described_class.send(:structure_invalidated?, tracker, 23_850.0, 23_800.0)
      expect(result).to be false
    end

    it 'returns nil gracefully when TickQuery fails' do
      allow(Live::TickQuery).to receive(:for_security).and_raise(StandardError)
      result = described_class.send(:resolve_underlying_ltp, 'NIFTY')
      expect(result).to be_nil
    end

    it 'skips structure invalidation when invalidation_price is nil in meta' do
      tick_query_spy = instance_spy(Live::TickQuery)
      allow(Live::TickQuery).to receive(:for_security).and_return(tick_query_spy)
      allow(tracker).to receive(:meta).and_return({
        'direction' => 'long_pe',
        'index_key' => 'NIFTY'
      })
      expect(Live::TickQuery).not_to have_received(:for_security)
    end
  end

  describe 'options-aware structure invalidation dual condition' do
    let(:tracker) do
      instance_double(
        PositionTracker,
        id: 1,
        meta: {
          'structure_invalidation_price' => 23_500.0,
          'index_key' => 'NIFTY',
          'direction' => 'long_ce',
          'entry_underlying_price' => 23_500.0,
          'peak_premium' => 200.0
        },
        created_at: 5.minutes.ago,
        entry_price: 180.0,
        quantity: 100,
        order_no: 'ORD-1'
      )
    end

    before do
      described_class.instance_variable_set(:@exit_config, nil)
      described_class.instance_variable_set(:@exit_config_expires_at, nil)

      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          exits: {
            structure_invalidation: {
              enabled: true,
              min_hold_seconds: 120,
              buffer_pct: 0.004,
              underlying_move_pct: 0.01,
              premium_drop_pct: 0.05
            }
          }
        }
      })

      allow(described_class).to receive_messages(
        early_exit_triggered?: false,
        loss_limit_hit?: false,
        emergency_peak_loss_exit_triggered?: false,
        profit_target_hit?: false,
        premium_momentum_failure_hit?: false,
        trailing_stop_hit?: false,
        time_based_exit?: false
      )
    end

    context 'when only underlying moved 1%+ (premium still near peak)' do
      before do
        allow(described_class).to receive(:resolve_underlying_ltp).and_return(23_147.0)
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return({
          pnl: -200, pnl_pct: -0.02, ltp: 196.0, hwm_pnl: 0
        })
      end

      it 'does NOT trigger structure invalidation' do
        result = described_class.check_exit_conditions(tracker)
        expect(result).to be_nil
      end
    end

    context 'when only premium dropped 5%+ (underlying stable)' do
      before do
        allow(described_class).to receive(:resolve_underlying_ltp).and_return(23_453.0)
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return({
          pnl: -1000, pnl_pct: -0.10, ltp: 180.0, hwm_pnl: 0
        })
      end

      it 'does NOT trigger structure invalidation' do
        result = described_class.check_exit_conditions(tracker)
        expect(result).to be_nil
      end
    end

    context 'when BOTH underlying moved 1%+ AND premium dropped 5%+' do
      before do
        allow(described_class).to receive(:resolve_underlying_ltp).and_return(23_147.0)
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return({
          pnl: -1500, pnl_pct: -0.15, ltp: 170.0, hwm_pnl: 0
        })
      end

      it 'triggers structure invalidation' do
        result = described_class.check_exit_conditions(tracker)
        expect(result).to include(exit: true)
        expect(result[:reason]).to include('STRUCTURE_INVALIDATION')
        expect(result[:path]).to eq('structure_invalidation')
      end
    end

    context 'when dual condition config is absent (backward compat)' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            exits: {
              structure_invalidation: {
                enabled: true,
                min_hold_seconds: 120,
                buffer_pct: 0.004
              }
            }
          }
        })

        allow(described_class).to receive(:resolve_underlying_ltp).and_return(23_400.0)
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return({
          pnl: -500, pnl_pct: -0.03, ltp: 150.0, hwm_pnl: 0
        })
      end

      it 'falls back to legacy single-condition check' do
        result = described_class.check_exit_conditions(tracker)
        expect(result).to include(exit: true)
        expect(result[:reason]).to include('STRUCTURE_INVALIDATION')
      end
    end
  end

  describe 'structure invalidation config check' do
    let(:tracker) do
      instance_double(
        PositionTracker,
        id: 1,
        meta: {
          'structure_invalidation_price' => 23_500.0,
          'index_key' => 'NIFTY',
          'direction' => 'long_ce'
        },
        created_at: 5.minutes.ago
      )
    end

    before do
      described_class.instance_variable_set(:@exit_config, nil)
      described_class.instance_variable_set(:@exit_config_expires_at, nil)

      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return({
        pnl: -500, pnl_pct: -0.03, ltp: 150.0, hwm_pnl: 0
      })
      allow(described_class).to receive_messages(resolve_underlying_ltp: 23_400.0, early_exit_triggered?: false, loss_limit_hit?: false, emergency_peak_loss_exit_triggered?: false, profit_target_hit?: false, premium_momentum_failure_hit?: false, trailing_stop_hit?: false, time_based_exit?: false)
    end

    context 'when structure_invalidation.enabled is false' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            exits: {
              structure_invalidation: {
                enabled: false,
                min_hold_seconds: 120,
                buffer_pct: 0.004
              }
            }
          }
        })
      end

      it 'skips structure invalidation check entirely' do
        result = described_class.check_exit_conditions(tracker)
        expect(result).to be_nil
      end
    end

    context 'when structure_invalidation.enabled is true' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            exits: {
              structure_invalidation: {
                enabled: true,
                min_hold_seconds: 120,
                buffer_pct: 0.004
              }
            }
          }
        })
      end

      it 'checks structure invalidation and exits when invalidated' do
        result = described_class.check_exit_conditions(tracker)
        expect(result).to include(exit: true)
        expect(result[:reason]).to include('STRUCTURE_INVALIDATION')
      end
    end
  end

  describe '#profit_target_hit? with trailing suppression' do
    let(:config) do
      {
        stop_loss: { type: 'static', value: 0.06 },
        take_profit: 0.12,
        trailing: { enabled: true, type: 'adaptive', activation_profit: 0.025, drop_threshold: 0.018 },
        early_exit: { enabled: false, profit_threshold: 0.07 },
        premium_momentum_failure: { enabled: false },
        time_based: { enabled: false, exit_time: '15:20' }
      }
    end

    before do
      described_class.instance_variable_set(:@exit_config, nil)
      described_class.instance_variable_set(:@exit_config_expires_at, nil)
      allow(described_class).to receive(:exit_config).and_return(config)
    end

    context 'when trailing is armed and profit exceeds TP' do
      let(:tracker) do
        instance_double(
          PositionTracker,
          id: 1,
          entry_price: 100.0,
          quantity: 100,
          meta: {},
          high_water_mark_pnl: 2_000.0
        )
      end

      let(:snapshot) { { pnl_pct: 0.15, ltp: 115.0, pnl: 1_500.0, hwm_pnl: 2_000.0 } }

      it 'suppresses TP and returns false' do
        result = described_class.send(:profit_target_hit?, tracker, snapshot)
        expect(result).to be false
      end
    end

    context 'when trailing is NOT armed and profit exceeds TP' do
      let(:tracker) do
        instance_double(
          PositionTracker,
          id: 1,
          entry_price: 100.0,
          quantity: 100,
          meta: {},
          high_water_mark_pnl: 200.0
        )
      end

      let(:snapshot) { { pnl_pct: 0.13, ltp: 113.0, pnl: 1_300.0, hwm_pnl: 200.0 } }

      it 'triggers TP normally' do
        result = described_class.send(:profit_target_hit?, tracker, snapshot)
        expect(result).to be true
      end
    end
  end

  describe '#percentage_pnl_exit_hit?' do
    # Trailing arms at 10% activation. At 141% profit, trailing is always armed.
    let(:snapshot_trailing_armed) { { pnl_pct: 1.4182, ltp: 669.0, pnl: 39_215.0, hwm_pnl: 39_215.0 } }
    # At 22% profit with no HWM (trailing not yet armed — hwm_pnl = 0)
    let(:snapshot_trailing_not_armed) { { pnl_pct: 0.22, ltp: 337.0, pnl: 6_035.0, hwm_pnl: 0.0 } }
    let(:snapshot_below_target) { { pnl_pct: 0.15, ltp: 319.0, pnl: 4_235.0, hwm_pnl: 0.0 } }

    let(:config_enabled) do
      {
        stop_loss: { type: 'static', value: 0.10 },
        take_profit: 0.25,
        trailing: { enabled: true, type: 'adaptive', activation_profit: 0.10, drop_threshold: 0.05 },
        early_exit: { enabled: false, profit_threshold: 0.07 },
        premium_momentum_failure: { enabled: false },
        time_based: { enabled: false, exit_time: '15:20' }
      }
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: { percentage_pnl_exit: { enabled: true, target_pct: 0.20 } },
        exit: {}
      })
      allow(described_class).to receive(:exit_config).and_return(config_enabled)
    end

    context 'when trailing is armed (position rode to 141.82%)' do
      it 'does NOT fire — trailing manages the position, runner is preserved' do
        # trailing_armed? returns true because hwm_pnl > entry_value * activation (0.10)
        # entry_value for tracker = 276.65 * 100 = 27_665; hwm = 39_215 > 2_766.5 → armed
        result = described_class.send(:percentage_pnl_exit_hit?, tracker, snapshot_trailing_armed)
        expect(result).to be false
      end
    end

    context 'when trailing is NOT armed and pnl exceeds target (trailing failed to engage)' do
      it 'fires as a safety net' do
        result = described_class.send(:percentage_pnl_exit_hit?, tracker, snapshot_trailing_not_armed)
        expect(result).to be true
      end
    end

    context 'when pnl is below target' do
      it 'does not fire' do
        result = described_class.send(:percentage_pnl_exit_hit?, tracker, snapshot_below_target)
        expect(result).to be false
      end
    end

    context 'when percentage_pnl_exit is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: { percentage_pnl_exit: { enabled: false, target_pct: 0.20 } },
          exit: {}
        })
      end

      it 'does not fire regardless of pnl_pct' do
        result = described_class.send(:percentage_pnl_exit_hit?, tracker, snapshot_trailing_not_armed)
        expect(result).to be false
      end
    end
  end
end
