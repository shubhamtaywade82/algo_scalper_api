# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::UnifiedExitChecker do
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 1,
      active?: true,
      entry_price: 100.0,
      quantity: 10,
      meta: { 'direction' => 'bullish' },
      instrument: nil,
      watchable: nil
    )
  end

  before do
    described_class.instance_variable_set(:@exit_config, nil)
    described_class.instance_variable_set(:@exit_config_expires_at, nil)
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        adaptive_trailing: {
          enabled: true,
          supertrend_flip_exit: false,
          counter_candles: 0
        }
      }
    )
  end

  describe '.check_exit_conditions' do
    it 'returns nil when pnl snapshot is missing' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(nil)

      expect(described_class.check_exit_conditions(tracker)).to be_nil
    end

    it 'returns adaptive hard stop when loss exceeds entry guard floor' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: -0.31, ltp: 69.0, pnl: -310.0, hwm_pnl: 0.0 }
      )

      result = described_class.check_exit_conditions(tracker)

      expect(result[:reason]).to eq('ADAPTIVE_TRAIL_HARD_STOP')
      expect(result[:path]).to eq('adaptive_trail')
    end

    it 'returns adaptive trail exit when giveback exceeds stage floor' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: 1.10, ltp: 210.0, pnl: 1100.0, hwm_pnl: 2000.0 }
      )

      result = described_class.check_exit_conditions(tracker)

      expect(result[:reason]).to eq('ADAPTIVE_TRAIL')
      expect(result[:path]).to eq('adaptive_trail')
    end

    it 'returns nil when price remains above the trail floor' do
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
        { pnl_pct: 0.05, ltp: 105.0, pnl: 50.0, hwm_pnl: 50.0 }
      )

      expect(described_class.check_exit_conditions(tracker)).to be_nil
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

  describe '#adaptive_trailing_exit? with tightening_multiplier' do
    let(:tiers) do
      [
        { min_profit: 0.15, drawdown: 0.10 },
        { min_profit: 0.50, drawdown: 0.06 },
        { min_profit: 1.00, drawdown: 0.03 }
      ]
    end

    let(:peak_profit_pct) { 1.4182 }

    let(:snapshot_at_hwm) { { hwm_pnl: 39_215.0, pnl: 39_215.0 } }
    let(:snapshot_2pct_drop) { { hwm_pnl: 39_215.0, pnl: 38_430.0 } }  # ~2% drop from HWM
    let(:snapshot_45pct_drop) { { hwm_pnl: 39_215.0, pnl: 37_553.0 } } # ~4.3% drop from HWM

    it 'does not fire at HWM with normal multiplier' do
      result = described_class.send(
        :adaptive_trailing_exit?,
        tracker,
        snapshot_at_hwm,
        peak_profit_pct,
        tiers,
        tightening_multiplier: 1.0
      )
      expect(result).to be false
    end

    it 'does not fire at 2% drop with normal multiplier (needs ~4.23%)' do
      result = described_class.send(
        :adaptive_trailing_exit?,
        tracker,
        snapshot_2pct_drop,
        peak_profit_pct,
        tiers,
        tightening_multiplier: 1.0
      )
      expect(result).to be false
    end

    it 'fires at ~4.3% drop with normal multiplier' do
      result = described_class.send(
        :adaptive_trailing_exit?,
        tracker,
        snapshot_45pct_drop,
        peak_profit_pct,
        tiers,
        tightening_multiplier: 1.0
      )
      expect(result).to be true
    end

    it 'fires at 2% drop with tightening multiplier 0.5' do
      result = described_class.send(
        :adaptive_trailing_exit?,
        tracker,
        snapshot_2pct_drop,
        peak_profit_pct,
        tiers,
        tightening_multiplier: 0.5
      )
      expect(result).to be true
    end

    it 'does not fire at HWM even with tightening multiplier 0.5' do
      result = described_class.send(
        :adaptive_trailing_exit?,
        tracker,
        snapshot_at_hwm,
        peak_profit_pct,
        tiers,
        tightening_multiplier: 0.5
      )
      expect(result).to be false
    end
  end

  describe 'underlying-context-aware trailing exit (integration)' do
    let(:exit_config) do
      {
        trailing: {
          enabled: true,
          type: 'adaptive',
          activation_profit: 0.15,
          drop_threshold: 0.15
        }
      }
    end

    let(:tracker) do
      instance_double(
        PositionTracker,
        id: 99,
        active?: true,
        entry_price: 276.65,
        quantity: 100,
        high_water_mark_pnl: 39_215.0,
        current_pnl_pct: 1.4182,
        symbol: 'SENSEX-Mar2026-75000-CE',
        order_no: 'ORD-SENSEX',
        meta: { 'index_key' => 'sensex', 'direction' => 'long_ce' }
      )
    end

    let(:snapshot_at_hwm) { { pnl_pct: 1.4182, ltp: 669.0, pnl: 39_215.0, hwm_pnl: 39_215.0 } }
    let(:snapshot_2pct_drop) { { pnl_pct: 1.38, ltp: 655.0, pnl: 38_430.0, hwm_pnl: 39_215.0 } }
    let(:snapshot_5pct_drop) { { pnl_pct: 1.35, ltp: 635.0, pnl: 37_260.0, hwm_pnl: 39_215.0 } }

    let(:healthy_state) do
      OpenStruct.new(
        trend_score: 45.0,
        bos_state: :intact,
        bos_direction: :neutral,
        atr_trend: :flat,
        atr_ratio: 0.95,
        mtf_confirm: true,
        ltp: 79_500.0,
        smc_bias_flip: false
      )
    end

    let(:bos_break_state) do
      OpenStruct.new(
        trend_score: 20.0,
        bos_state: :broken,
        bos_direction: :bearish,
        atr_trend: :rising,
        atr_ratio: 1.1,
        mtf_confirm: false,
        ltp: 78_200.0,
        smc_bias_flip: false
      )
    end

    let(:weak_trend_state) do
      OpenStruct.new(
        trend_score: 10.0,
        bos_state: :intact,
        bos_direction: :neutral,
        atr_trend: :flat,
        atr_ratio: 0.80,
        mtf_confirm: false,
        ltp: 79_000.0,
        smc_bias_flip: false
      )
    end

    before do
      described_class.instance_variable_set(:@exit_config, nil)
      described_class.instance_variable_set(:@exit_config_expires_at, nil)
      allow(described_class).to receive(:exit_config).and_return(exit_config)

      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          underlying_context_exit: {
            enabled: true,
            trend_score_threshold: 15,
            atr_ratio_threshold: 0.65,
            tightening_multiplier: 0.5
          },
          institutional_trailing: {
            sensex: {
              activation_trigger: 0.15,
              trailing_distance: 0.15,
              adaptive_drawdown: [
                { min_profit: 0.15, drawdown: 0.10 },
                { min_profit: 0.50, drawdown: 0.06 },
                { min_profit: 1.00, drawdown: 0.03 }
              ]
            }
          },
          exits: {},
          percentage_pnl_exit: { enabled: false }
        },
        exit: {}
      })

      allow(Positions::ActiveCache.instance).to receive(:get_by_tracker_id).and_return(nil)
      allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(healthy_state)
      allow(Orders::Analyzer).to receive(:new).and_return(instance_double(Orders::Analyzer, recommended_sl: nil))

      allow(described_class).to receive_messages(
        portfolio_floor_breach?: false,
        early_exit_triggered?: false,
        loss_limit_hit?: false,
        emergency_peak_loss_exit_triggered?: false,
        profit_target_hit?: false,
        percentage_pnl_exit_hit?: false,
        premium_momentum_failure_hit?: false,
        check_structure_invalidation: nil,
        check_smc_navigator_exit: nil,
        time_based_exit?: false
      )
    end

    context 'when underlying is healthy and position is at HWM' do
      before do
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(snapshot_at_hwm)
      end

      it 'does not exit' do
        result = described_class.check_exit_conditions(tracker)
        expect(result).to be_nil
      end
    end

    context 'when BOS breaks against position' do
      before do
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(snapshot_at_hwm)
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(bos_break_state)
      end

      it 'exits immediately with UNDERLYING_STRUCTURE_BREAK' do
        result = described_class.check_exit_conditions(tracker)
        expect(result).not_to be_nil
        expect(result[:exit]).to be true
        expect(result[:reason]).to include('UNDERLYING_STRUCTURE_BREAK')
        expect(result[:path]).to eq('underlying_context_exit')
      end
    end

    context 'when trend is weak and position drops 2% from HWM' do
      before do
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(snapshot_2pct_drop)
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(weak_trend_state)
      end

      it 'exits via trailing stop due to tightened allowed_dd' do
        result = described_class.check_exit_conditions(tracker)
        expect(result).not_to be_nil
        expect(result[:exit]).to be true
        expect(result[:reason]).to eq('TRAILING_STOP')
        expect(result[:path]).to eq('trailing_stop')
      end
    end

    context 'when underlying is healthy and position drops 5% from HWM' do
      before do
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(snapshot_5pct_drop)
      end

      it 'exits via normal trailing' do
        result = described_class.check_exit_conditions(tracker)
        expect(result).not_to be_nil
        expect(result[:exit]).to be true
        expect(result[:reason]).to eq('TRAILING_STOP')
      end
    end

    context 'when trailing is not armed (hwm_pnl = 0)' do
      before do
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(
          { pnl_pct: 0.22, ltp: 337.0, pnl: 6_035.0, hwm_pnl: 0.0 }
        )
      end

      it 'does not call UnderlyingMonitor.evaluate' do
        described_class.check_exit_conditions(tracker)
        expect(Live::UnderlyingMonitor).not_to have_received(:evaluate)
      end
    end
  end
end
