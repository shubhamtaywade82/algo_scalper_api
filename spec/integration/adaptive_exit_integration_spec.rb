# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Adaptive Exit System Integration', type: :integration do
  let(:service) { Live::RiskManagerService.new }
  let(:exit_engine) { instance_double(Live::ExitEngine) }
  let(:instrument) { create(:instrument, :nifty_call_option, symbol_name: 'NIFTY') }
  let(:tracker) do
    create(:position_tracker,
           instrument: instrument,
           status: 'active',
           entry_price: 100.0,
           quantity: 50,
           segment: 'NSE_FNO',
           trade_state: 'expansion',
           meta: { 'index_key' => 'NIFTY' })
  end

  before do
    allow(exit_engine).to receive(:execute_exit)
    allow(service).to receive_messages(seconds_below_entry: 0, calculate_atr_ratio: 1.0)
    Positions::TrailingConfig.reset_config!

    # Mock RedisPnlCache
    allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_wrap_original do |_method, *args|
      args.first == tracker.id ? pnl_data : nil
    end

    # Mock ActiveCache (used by TrailingEngine)
    allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([tracker])
    active_cache = Positions::ActiveCache.instance
    allow(active_cache).to receive(:get_by_tracker_id).and_wrap_original do |_method, *args|
      if args.first == tracker.id && defined?(pnl_data)
        Positions::PositionData.new(
          tracker_id: tracker.id,
          security_id: tracker.security_id,
          segment: tracker.segment,
          entry_price: tracker.entry_price,
          quantity: tracker.quantity,
          current_ltp: pnl_data[:ltp] || (tracker.entry_price.to_f * (1 + pnl_data[:pnl_pct].to_f)),
          pnl: pnl_data[:pnl],
          pnl_pct: pnl_data[:pnl_pct],
          high_water_mark: pnl_data[:hwm_pnl],
          peak_profit_pct: pnl_data[:peak_profit_pct] || pnl_data[:hwm_pnl_pct] || (pnl_data[:hwm_pnl] && tracker.entry_price.to_f > 0 ? (pnl_data[:hwm_pnl] / (tracker.entry_price.to_f * tracker.quantity)) : 0.05),
          position_direction: %w[long_ce long_pe].include?(tracker.side) ? :long : :short,
          index_key: 'NIFTY'
        )
      end
    end
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
            peak_drawdown_activation_profit_pct: 0.03,
            peak_drawdown_exit_pct: 0.02,
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
        Positions::TrailingConfig.reset_config!
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
          # Peak: 5%, Current: 2%, Drop: 3%
          # With conservative config, should trigger peak_drawdown_exit
          puts "DEBUG: TrailingConfig.config: #{Positions::TrailingConfig.config.inspect}"
          expect(exit_engine).to receive(:execute_exit).with(
            tracker,
            match(/ADAPTIVE_TRAILING_STOP|TRAILING_STOP|peak_drawdown_exit/)
          )
          service.enforce_dynamic_trailing_stops(exit_engine: exit_engine)
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
            peak_drawdown_exit_pct: 0.05,
            tiered_drawdown_thresholds: {
              low: 0.05,
              medium: 0.05,
              high: 0.05
            },
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
        Positions::TrailingConfig.reset_config!
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
          service.enforce_dynamic_trailing_stops(exit_engine: exit_engine)
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
        Positions::TrailingConfig.reset_config!
      end

      it 'invokes run_interval_enforcement_if_needed from monitor_loop' do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([])
        allow(service).to receive(:run_interval_enforcement_if_needed)

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
        Positions::TrailingConfig.reset_config!
      end

      it 'falls back to static SL/TP only' do
        # Should only check static SL/TP
        expect(exit_engine).not_to receive(:execute_exit) # TP is +5%, we're at +5%, so no exit
        service.send(:run_interval_enforcement_if_needed, exit_engine)
        service.enforce_dynamic_trailing_stops(exit_engine: exit_engine)
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
        expect { service.enforce_dynamic_trailing_stops(exit_engine: exit_engine) }.not_to raise_error
        expect { service.enforce_premium_momentum_failure(exit_engine: exit_engine) }.not_to raise_error
      end
    end
  end
end
