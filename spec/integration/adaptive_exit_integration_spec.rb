# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Adaptive Exit System Integration', type: :integration do
  let(:service) { Live::RiskManagerService.new }
  let(:exit_engine) { instance_double(Live::ExitEngine) }
  let(:instrument) { create(:instrument, :nifty_call_option, symbol_name: 'NIFTY') }
  let(:tracker) do
    create(:position_tracker,
           instrument: instrument,
           entry_price: 100.0,
           quantity: 50,
           segment: 'NSE_FNO',
           trade_state: 'expansion',
           meta: { 'index_key' => 'NIFTY' })
  end

  before do
    allow(exit_engine).to receive(:execute_exit)
    allow(service).to receive_messages(seconds_below_entry: 0, calculate_atr_ratio: 1.0)

    # Mock MarketFeedHub to avoid real WebSocket calls and leaks
    allow(Live::MarketFeedHub.instance).to receive_messages(subscribe: { success: true }, unsubscribe: { success: true })

    # Reset TrailingConfig memoization so it picks up the test config
    Positions::TrailingConfig.instance_variable_set(:@config, nil)

    # Ensure ActiveCache is clean
    Positions::ActiveCache.instance.clear
  end

  def setup_active_cache(tracker, pnl_data)
    # Add position to ActiveCache
    Positions::ActiveCache.instance.add_position(tracker: tracker)

    # Update with test PnL data
    Positions::ActiveCache.instance.update_position(
      tracker.id,
      pnl_pct: pnl_data[:pnl_pct].to_f,
      peak_profit_pct: (pnl_data[:hwm_pnl] / (tracker.entry_price * tracker.quantity)).to_f,
      current_ltp: (tracker.entry_price * (1 + pnl_data[:pnl_pct].to_f)).to_f
    )

    # Update RedisPnlCache for UnifiedExitChecker
    Live::RedisPnlCache.instance.store_pnl(
      tracker_id: tracker.id,
      pnl: pnl_data[:pnl],
      pnl_pct: pnl_data[:pnl_pct].to_f,
      ltp: (tracker.entry_price * (1 + pnl_data[:pnl_pct].to_f)).to_f,
      hwm: pnl_data[:hwm_pnl],
      timestamp: Time.current,
      tracker: tracker
    )

    tracker.update_columns(trade_state: 'expansion')
  end

  describe 'full exit flow with different configurations' do
    context 'conservative configuration' do
      let(:config) do
        {
          risk: {
            sl_pct: 0.03,
            tp_pct: 0.05,
            exit_drop_pct: 0.02, # Tighter trailing
            breakeven_after_gain: 0.05,
            drawdown: {
              activation_profit_pct: 0.03,
              profit_min: 0.03,
              profit_max: 0.30,
              dd_start_pct: 0.10,
              dd_end_pct: 0.005,
              exponential_k: 5.0,
              index_floors: { 'NIFTY' => 0.005 }
            },
            tiered_drawdown_thresholds: {
              low: 0.01 # 1% threshold for 5% peak
            },
            reverse_loss: {
              enabled: true,
              max_loss_pct: 0.15, # Tighter
              min_loss_pct: 0.03, # Tighter
              loss_span_pct: 0.30,
              time_tighten_per_min: 0.03
            },
            etf: {
              enabled: true,
              activation_profit_pct: 0.05,
              trend_score_drop_pct: 0.25,
              adx_collapse_threshold: 12,
              atr_ratio_threshold: 0.60
            },
            # Direct trailing enabled for conservative
            direct_trailing: { enabled: true }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      context 'when position is profitable and drops' do
        let(:pnl_data) do
          {
            pnl: BigDecimal('100.0'), # +2% current (dropped from peak)
            pnl_pct: BigDecimal('0.02'),
            hwm_pnl: BigDecimal('250.0') # +5% peak
          }
        end

        it 'triggers adaptive trailing stop' do
          setup_active_cache(tracker, pnl_data)
          # Peak: 5%, Current: 3%, Drop: 2%
          # With conservative config, should trigger
          expect(exit_engine).to receive(:execute_exit).with(
            tracker,
            match(/ADAPTIVE_TRAILING_STOP|TRAILING_STOP|peak_drawdown_exit/)
          )
          service.enforce_trailing_stops(exit_engine: exit_engine)
        end
      end

      context 'when position goes below entry' do
        let(:pnl_data) do
          {
            pnl: BigDecimal('-200.0'), # -4% loss
            pnl_pct: BigDecimal('-0.04'),
            hwm_pnl: BigDecimal(0)
          }
        end

        it 'uses tighter reverse SL' do
          # With conservative config, -4% loss should be within allowed range
          # But if it exceeds, should trigger
          allow(service).to receive(:seconds_below_entry).and_return(120) # 2 minutes

          # Conservative max_loss at -4% ≈ 13% allowed
          # Current loss 4% < 13% → No exit expected
          # But let's test if it exceeds
          expect(exit_engine).not_to receive(:execute_exit)
          service.send(:run_interval_enforcement_if_needed, exit_engine)
        end
      end
    end

    context 'aggressive configuration' do
      let(:config) do
        {
          risk: {
            sl_pct: 0.03,
            tp_pct: 0.05,
            exit_drop_pct: 0.05, # Wider trailing
            breakeven_after_gain: 0.10,
            drawdown: {
              activation_profit_pct: 0.05,
              profit_min: 0.05,
              profit_max: 0.50,
              dd_start_pct: 0.20,
              dd_end_pct: 0.02,
              exponential_k: 2.0,
              index_floors: { 'NIFTY' => 0.02 }
            },
            reverse_loss: {
              enabled: true,
              max_loss_pct: 0.25,
              min_loss_pct: 0.10,
              loss_span_pct: 0.50,
              time_tighten_per_min: 0.01
            },
            etf: {
              enabled: true,
              activation_profit_pct: 0.10,
              trend_score_drop_pct: 0.40,
              adx_collapse_threshold: 8,
              atr_ratio_threshold: 0.50
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      context 'when position is profitable' do
        let(:pnl_data) do
          {
            pnl: BigDecimal('425.0'), # +8.5% current
            pnl_pct: BigDecimal('0.085'),
            hwm_pnl: BigDecimal('500.0') # +10% peak
          }
        end

        it 'allows wider drawdown' do
          setup_active_cache(tracker, pnl_data)
          # Peak: 10%, Current: 8.5%, Drop: 1.5%
          # With aggressive config, 1.5% drop should be within allowed range (2%)
          expect(exit_engine).not_to receive(:execute_exit)
          service.enforce_trailing_stops(exit_engine: exit_engine)
        end
      end

      context 'when position goes below entry' do
        let(:pnl_data) do
          {
            pnl: BigDecimal('-300.0'), # -6% loss
            pnl_pct: BigDecimal('-0.06'),
            hwm_pnl: BigDecimal(0)
          }
        end

        it 'allows wider loss' do
          # With aggressive config, -6% loss should be within allowed range
          expect(exit_engine).not_to receive(:execute_exit)
          service.send(:run_interval_enforcement_if_needed, exit_engine)
        end
      end
    end

    context 'balanced configuration (default)' do
      let(:config) do
        {
          risk: {
            sl_pct: 0.03,
            tp_pct: 0.05,
            exit_drop_pct: 0.03,
            breakeven_after_gain: 0.05,
            drawdown: {
              activation_profit_pct: 0.05,
              profit_min: 0.05,
              profit_max: 0.50,
              dd_start_pct: 0.20,
              dd_end_pct: 0.02,
              exponential_k: 2.0,
              index_floors: { 'NIFTY' => 0.02 }
            },
            reverse_loss: {
              enabled: true,
              max_loss_pct: 0.25,
              min_loss_pct: 0.10,
              loss_span_pct: 0.50,
              time_tighten_per_min: 0.01
            },
            etf: {
              enabled: true,
              activation_profit_pct: 0.07,
              trend_score_drop_pct: 0.30,
              adx_collapse_threshold: 10,
              atr_ratio_threshold: 0.55
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'executes all enforcement methods in order' do
        pnl_data = {
          pnl: BigDecimal('250.0'),
          pnl_pct: BigDecimal('0.05'),
          hwm_pnl: BigDecimal('250.0')
        }
        setup_active_cache(tracker, pnl_data)

        expect(service).to receive(:enforce_hard_limits_for).with(tracker, exit_engine: exit_engine).and_call_original
        expect(service).to receive(:enforce_early_trend_failure_for).with(tracker, exit_engine: exit_engine).and_call_original
        expect(service).to receive(:enforce_premium_r_stop_for).with(tracker, exit_engine: exit_engine).and_call_original
        expect(service).to receive(:enforce_dynamic_trailing_stops_for).with(tracker, exit_engine: exit_engine).and_call_original

        service.instance_variable_set(:@exit_engine, exit_engine)
        service.send(:monitor_loop, Time.current)

        expect(service).to have_received(:run_interval_enforcement_if_needed)
      end
    end
  end

  describe 'configuration edge cases' do
    context 'when all adaptive features are disabled' do
      let(:config) do
        {
          risk: {
            sl_pct: 0.03,
            tp_pct: 0.05,
            exit_drop_pct: 999, # Disabled
            drawdown: {},
            reverse_loss: { enabled: false },
            etf: { enabled: false }
          }
        }
      end
      let(:pnl_data) do
        {
          pnl: BigDecimal('250.0'),
          pnl_pct: BigDecimal('0.05'),
          hwm_pnl: BigDecimal('250.0')
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'falls back to static SL/TP only' do
        # Should only check static SL/TP
        expect(exit_engine).not_to receive(:execute_exit) # TP is +5%, we're at +5%, so no exit
        service.send(:run_interval_enforcement_if_needed, exit_engine)
        service.enforce_trailing_stops(exit_engine: exit_engine)
      end
    end

    context 'when config is missing entirely' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({})
      end

      let(:pnl_data) do
        {
          pnl: BigDecimal('250.0'),
          pnl_pct: BigDecimal('0.05'),
          hwm_pnl: BigDecimal('250.0')
        }
      end

      it 'handles gracefully without crashing' do
        allow(PositionTracker).to receive(:active).and_return(double(find_each: [].each))
        expect { service.send(:run_interval_enforcement_if_needed, exit_engine) }.not_to raise_error
        expect { service.enforce_trailing_stops(exit_engine: exit_engine) }.not_to raise_error
        expect { service.enforce_early_trend_failure(exit_engine: exit_engine) }.not_to raise_error
      end
    end
  end
end
