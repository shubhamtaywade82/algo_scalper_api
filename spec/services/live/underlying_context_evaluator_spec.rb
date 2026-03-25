# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::UnderlyingContextEvaluator do
  # Include the module into a test host that mimics UnifiedExitChecker's singleton shape
  let(:host) do
    host_class = Class.new do
      class << self
        include Live::UnderlyingContextEvaluator

        # Stub trailing_armed? (the module calls this from exit_config)
        def exit_config
          {
            trailing: { enabled: true, type: 'adaptive', activation_profit: 0.10,
                        drop_threshold: 0.05 }
          }
        end
      end
    end
    host_class
  end

  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 42,
      entry_price: 276.65,
      quantity: 100,
      symbol: 'SENSEX-Mar2026-75000-CE',
      order_no: 'ORD-TEST',
      meta: { 'index_key' => 'sensex', 'direction' => 'long_ce' }
    )
  end

  # snapshot where trailing IS armed: hwm_pnl >> entry_value * activation (0.10)
  # entry_value = 276.65 * 100 = 27_665; activation = 10% = 2_766.5
  # hwm = 39_215 > 2_766.5 → armed
  let(:snapshot_armed)     { { pnl_pct: 1.4182, ltp: 669.0, pnl: 39_215.0, hwm_pnl: 39_215.0 } }
  # snapshot where trailing is NOT armed: hwm_pnl = 0
  let(:snapshot_not_armed) { { pnl_pct: 0.05, ltp: 290.0, pnl: 1_335.0, hwm_pnl: 0.0 } }

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

  let(:bos_break_against_long) do
    OpenStruct.new(
      trend_score: 20.0,
      bos_state: :broken,
      bos_direction: :bearish,   # bearish BOS breaks long_ce thesis
      atr_trend: :rising,
      atr_ratio: 1.1,
      mtf_confirm: false,
      ltp: 78_200.0,
      smc_bias_flip: false
    )
  end

  let(:weak_trend_state) do
    OpenStruct.new(
      trend_score: 10.0,           # below threshold of 15
      bos_state: :intact,
      bos_direction: :neutral,
      atr_trend: :flat,
      atr_ratio: 0.80,
      mtf_confirm: false,
      ltp: 79_000.0,
      smc_bias_flip: false
    )
  end

  let(:atr_collapse_state) do
    OpenStruct.new(
      trend_score: 25.0,           # healthy score
      bos_state: :intact,
      bos_direction: :neutral,
      atr_trend: :falling,
      atr_ratio: 0.55,             # below threshold of 0.65
      mtf_confirm: true,
      ltp: 79_200.0,
      smc_bias_flip: false
    )
  end

  let(:dual_weakness_state) do
    OpenStruct.new(
      trend_score: 8.0,            # weak
      bos_state: :intact,
      bos_direction: :neutral,
      atr_trend: :falling,
      atr_ratio: 0.50,             # collapsing
      mtf_confirm: false,
      ltp: 78_800.0,
      smc_bias_flip: false
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        underlying_context_exit: {
          enabled: true,
          trend_score_threshold: 15,
          atr_ratio_threshold: 0.65,
          tightening_multiplier: 0.5
        }
      }
    })
    # Default: return healthy state unless overridden in individual contexts
    allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(healthy_state)
    # Default: ActiveCache returns nil (simulate missing pos_data gracefully)
    allow(Positions::ActiveCache.instance).to receive(:get_by_tracker_id).and_return(nil)
  end

  describe '#evaluate_underlying_context' do
    context 'when trailing is NOT armed (hwm_pnl = 0)' do
      it 'returns :hold with multiplier 1.0 without calling UnderlyingMonitor' do
        result = host.evaluate_underlying_context(tracker, snapshot_not_armed)
        expect(result).to eq({ action: :hold, multiplier: 1.0, reason: nil })
        expect(Live::UnderlyingMonitor).not_to have_received(:evaluate)
      end
    end

    context 'when underlying_context_exit is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: { underlying_context_exit: { enabled: false } }
        })
      end

      it 'returns :hold with multiplier 1.0' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result).to eq({ action: :hold, multiplier: 1.0, reason: nil })
      end
    end

    context 'when UnderlyingMonitor returns nil / raises' do
      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(nil) }

      it 'returns :hold with multiplier 1.0' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result).to eq({ action: :hold, multiplier: 1.0, reason: nil })
      end
    end

    context 'when underlying is healthy' do
      it 'returns :hold with multiplier 1.0' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result).to eq({ action: :hold, multiplier: 1.0, reason: nil })
      end
    end

    context 'when BOS breaks against a long_ce position (bearish BOS)' do
      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(bos_break_against_long) }

      it 'returns :exit with UNDERLYING_STRUCTURE_BREAK reason' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:exit)
        expect(result[:reason]).to include('UNDERLYING_STRUCTURE_BREAK')
        expect(result[:multiplier]).to be_nil.or be_a(Numeric) # multiplier irrelevant on :exit
      end
    end

    context 'when BOS breaks against a long_pe position (bullish BOS)' do
      let(:pe_tracker) do
        instance_double(
          PositionTracker,
          id: 43,
          entry_price: 200.0,
          quantity: 50,
          symbol: 'SENSEX-Mar2026-74000-PE',
          order_no: 'ORD-PE',
          meta: { 'index_key' => 'sensex', 'direction' => 'long_pe' }
        )
      end

      let(:bos_break_against_short) do
        OpenStruct.new(
          trend_score: 20.0,
          bos_state: :broken,
          bos_direction: :bullish,  # bullish BOS breaks long_pe thesis
          atr_trend: :rising,
          atr_ratio: 1.1,
          mtf_confirm: false,
          ltp: 80_000.0,
          smc_bias_flip: false
        )
      end

      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(bos_break_against_short) }

      it 'returns :exit with UNDERLYING_STRUCTURE_BREAK reason' do
        result = host.evaluate_underlying_context(pe_tracker, snapshot_armed)
        expect(result[:action]).to eq(:exit)
        expect(result[:reason]).to include('UNDERLYING_STRUCTURE_BREAK')
      end
    end

    context 'when trend is weak AND ATR is collapsing (dual weakness)' do
      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(dual_weakness_state) }

      it 'returns :exit with UNDERLYING_DUAL_WEAKNESS reason' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:exit)
        expect(result[:reason]).to include('UNDERLYING_DUAL_WEAKNESS')
      end
    end

    context 'when trend is weak but ATR is healthy' do
      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(weak_trend_state) }

      it 'returns :tighten with configured multiplier (0.5)' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:tighten)
        expect(result[:multiplier]).to eq(0.5)
        expect(result[:reason]).to include('UNDERLYING_WEAKENING')
      end
    end

    context 'when ATR is collapsing but trend score is healthy' do
      before { allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(atr_collapse_state) }

      it 'returns :tighten with configured multiplier (0.5)' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:tighten)
        expect(result[:multiplier]).to eq(0.5)
        expect(result[:reason]).to include('UNDERLYING_WEAKENING')
      end
    end

    context 'when smc_bias_flip is true but no other weakness' do
      before do
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(
          OpenStruct.new(
            trend_score: 40.0, bos_state: :intact, bos_direction: :neutral,
            atr_trend: :flat, atr_ratio: 0.90, mtf_confirm: true,
            ltp: 79_500.0, smc_bias_flip: true
          )
        )
      end

      it 'returns :hold — smc_bias_flip is excluded from this evaluator' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:hold)
      end
    end

    context 'multiplier is always a Float, never nil' do
      it 'hold path returns Float multiplier' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:multiplier]).to be_a(Float)
      end

      it 'not-armed path returns Float multiplier' do
        result = host.evaluate_underlying_context(tracker, snapshot_not_armed)
        expect(result[:multiplier]).to be_a(Float)
      end

      it 'tighten path returns Float multiplier' do
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(weak_trend_state)
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:multiplier]).to be_a(Float)
      end
    end

    context 'with configurable thresholds' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            underlying_context_exit: {
              enabled: true,
              trend_score_threshold: 25,   # higher threshold
              atr_ratio_threshold: 0.65,
              tightening_multiplier: 0.3
            }
          }
        })
        # trend_score: 10 < 25 (new threshold) → weak
        allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(weak_trend_state)
      end

      it 'uses the configured trend_score_threshold' do
        result = host.evaluate_underlying_context(tracker, snapshot_armed)
        expect(result[:action]).to eq(:tighten)
        expect(result[:multiplier]).to eq(0.3)
      end
    end
  end
end
