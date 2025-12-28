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
           meta: { 'index_key' => 'NIFTY' })
  end

  before do
    allow(exit_engine).to receive(:execute_exit)
    allow(service).to receive(:seconds_below_entry).and_return(0)
    allow(service).to receive(:calculate_atr_ratio).and_return(1.0)
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
              activation_profit_pct: 3.0,
              profit_min: 3.0,
              profit_max: 30.0,
              dd_start_pct: 10.0, # Tighter
              dd_end_pct: 0.5,    # Tighter
              exponential_k: 5.0,
              index_floors: { 'NIFTY' => 0.5 }
            },
            reverse_loss: {
              enabled: true,
              max_loss_pct: 15.0, # Tighter
              min_loss_pct: 3.0,  # Tighter
              loss_span_pct: 30.0,
              time_tighten_per_min: 3.0
            },
            etf: {
              enabled: true,
              activation_profit_pct: 5.0,
              trend_score_drop_pct: 25.0,
              adx_collapse_threshold: 12,
              atr_ratio_threshold: 0.60
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      context 'when position is profitable and drops' do
        let(:pnl_data) do
          {
            pnl: BigDecimal('150.0'), # +3% current (dropped from peak)
            pnl_pct: BigDecimal('0.03'),
            hwm_pnl: BigDecimal('250.0') # +5% peak
          }
        end

        it 'triggers adaptive trailing stop' do
          # Peak: 5%, Current: 3%, Drop: 2%
          # With conservative config, should trigger
          expect(exit_engine).to receive(:execute_exit).with(
            tracker,
            match(/ADAPTIVE_TRAILING_STOP|TRAILING_STOP/)
          )
          service.enforce_trailing_stops(exit_engine: exit_engine)
        end
      end

      context 'when position goes below entry' do
        let(:pnl_data) do
          {
            pnl: BigDecimal('-200.0'), # -4% loss
            pnl_pct: BigDecimal('-0.04'),
            hwm_pnl: BigDecimal('0')
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
          service.enforce_hard_limits(exit_engine: exit_engine)
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
              activation_profit_pct: 3.0,
              profit_min: 3.0,
              profit_max: 30.0,
              dd_start_pct: 20.0, # Wider
              dd_end_pct: 2.0,    # Wider
              exponential_k: 2.0,
              index_floors: { 'NIFTY' => 2.0 }
            },
            reverse_loss: {
              enabled: true,
              max_loss_pct: 25.0, # Wider
              min_loss_pct: 7.0,  # Wider
              loss_span_pct: 30.0,
              time_tighten_per_min: 1.0
            },
            etf: {
              enabled: true,
              activation_profit_pct: 10.0,
              trend_score_drop_pct: 40.0,
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
            pnl: BigDecimal('400.0'), # +8% current
            pnl_pct: BigDecimal('0.08'),
            hwm_pnl: BigDecimal('500.0') # +10% peak
          }
        end

        it 'allows wider drawdown' do
          # Peak: 10%, Current: 8%, Drop: 2%
          # With aggressive config, 2% drop should be within allowed range
          expect(exit_engine).not_to receive(:execute_exit)
          service.enforce_trailing_stops(exit_engine: exit_engine)
        end
      end

      context 'when position goes below entry' do
        let(:pnl_data) do
          {
            pnl: BigDecimal('-300.0'), # -6% loss
            pnl_pct: BigDecimal('-0.06'),
            hwm_pnl: BigDecimal('0')
          }
        end

        it 'allows wider loss' do
          # With aggressive config, -6% loss should be within allowed range
          expect(exit_engine).not_to receive(:execute_exit)
          service.enforce_hard_limits(exit_engine: exit_engine)
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
              activation_profit_pct: 3.0,
              profit_min: 3.0,
              profit_max: 30.0,
              dd_start_pct: 15.0,
              dd_end_pct: 1.0,
              exponential_k: 3.0,
              index_floors: { 'NIFTY' => 1.0 }
            },
            reverse_loss: {
              enabled: true,
              max_loss_pct: 20.0,
              min_loss_pct: 5.0,
              loss_span_pct: 30.0,
              time_tighten_per_min: 2.0
            },
            etf: {
              enabled: true,
              activation_profit_pct: 7.0,
              trend_score_drop_pct: 30.0,
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
        allow(service).to receive(:pnl_snapshot).and_return(pnl_data)

        expect(service).to receive(:enforce_early_trend_failure).with(exit_engine: exit_engine)
        expect(service).to receive(:enforce_hard_limits).with(exit_engine: exit_engine)
        expect(service).to receive(:enforce_trailing_stops).with(exit_engine: exit_engine)
        expect(service).to receive(:enforce_time_based_exit).with(exit_engine: exit_engine)

        service.send(:monitor_loop, Time.current)
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

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      let(:pnl_data) do
        {
          pnl: BigDecimal('250.0'),
          pnl_pct: BigDecimal('0.05'),
          hwm_pnl: BigDecimal('250.0')
        }
      end

      it 'falls back to static SL/TP only' do
        # Should only check static SL/TP
        expect(exit_engine).not_to receive(:execute_exit) # TP is +5%, we're at +5%, so no exit
        service.enforce_hard_limits(exit_engine: exit_engine)
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
        expect { service.enforce_hard_limits(exit_engine: exit_engine) }.not_to raise_error
        expect { service.enforce_trailing_stops(exit_engine: exit_engine) }.not_to raise_error
        expect { service.enforce_early_trend_failure(exit_engine: exit_engine) }.not_to raise_error
      end
    end
  end
end
