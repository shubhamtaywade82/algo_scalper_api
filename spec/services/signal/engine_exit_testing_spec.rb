# frozen_string_literal: true

require 'rails_helper'

# Tests that the Signal::Engine.run_for pipeline executes correctly in
# exit_testing mode. Prior to the fix, run_for crashed with:
#   NoMethodError: undefined method `trading_context_blocked?' for class Signal::Engine
# These specs verify the private methods exist and behavior is correct.
RSpec.describe Signal::Engine, 'exit_testing mode pipeline' do
  let(:index_cfg) do
    { key: 'NIFTY', segment: 'IDX_I', sid: '13', capital_alloc_pct: 0.30 }
  end

  let(:instrument) { instance_double(Instrument) }
  let(:series) { build(:candle_series, :five_minute, :with_candles) }

  let(:supertrend_result) do
    { trend: :bearish, last_value: 22_500.0, flipped: false }
  end

  let(:adx_result) { 45.0 }

  let(:primary_analysis) do
    {
      status: :ok,
      direction: :bearish,
      supertrend: supertrend_result,
      adx_value: adx_result,
      series: series,
      last_candle_timestamp: Time.current
    }
  end

  let(:signals_cfg) do
    {
      primary_timeframe: '1m',
      supertrend: { period: 12, multiplier: 2.5 },
      adx: { min_strength: 20 },
      enable_adx_filter: true,
      enable_index_ta_filter: false,
      enable_trading_context_gate: false,
      enable_smc_avrz_permission: false,
      enable_smc_decision_alignment: false,
      use_strategy_recommendations: false,
      enable_confirmation_timeframe: false,
      validation_mode: 'exit_testing'
    }
  end

  before do
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
    allow(AlgoConfig).to receive(:run_mode).and_return('exit_testing')
    allow(AlgoConfig).to receive(:fetch).and_return({ signals: signals_cfg })
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)

    allow(instrument).to receive(:candle_series).and_return(series)
    allow(instrument).to receive(:expiry_list).and_return([Date.tomorrow])
    allow(instrument).to receive(:fetch_option_chain).and_return(nil)

    allow(described_class).to receive(:analyze_timeframe).and_return(primary_analysis)

    allow(IndexTechnicalAnalyzer).to receive(:new).and_return(
      instance_double(IndexTechnicalAnalyzer,
                      call: { success: true },
                      success?: true,
                      error: nil,
                      result: { signal: :neutral, confidence: 0.5,
                                bias_summary: { summary: { bias: 'neutral' } },
                                indicators: nil })
    )

    allow(Signal::StateTracker).to receive(:record).and_return({ count: 1, multiplier: 1 })
    allow(Signal::StateTracker).to receive(:reset)

    allow(Options::DerivativeChainAnalyzer).to receive(:new).and_return(
      instance_double(Options::DerivativeChainAnalyzer, nearest_expiry: Date.tomorrow)
    )

    allow(TradingSignal).to receive(:create_from_analysis).and_call_original
  end

  describe '.run_for' do
    context 'when run_mode is exit_testing' do
      it 'does not raise NoMethodError for trading_context_blocked?' do
        expect { described_class.run_for(index_cfg) }.not_to raise_error
      end

      it 'defines all private methods required by run_for' do
        engine_private_methods = described_class.private_methods(false)
        expect(engine_private_methods).to include(:trading_context_blocked?)
        expect(engine_private_methods).to include(:evaluate_entry_quality)
        expect(engine_private_methods).to include(:execute_execution_gates)
        expect(engine_private_methods).to include(:execute_options_analysis)
        expect(engine_private_methods).to include(:build_diagnostic_metadata)
        expect(engine_private_methods).to include(:execute_entry_gate)
        expect(engine_private_methods).to include(:trigger_entry_flow)
      end

      it 'creates a TradingSignal with effective_timeframe in metadata' do
        allow(Options::ChainAnalyzer).to receive(:pick_strikes_with_qualification).and_return([])

        described_class.run_for(index_cfg)

        last_signal = TradingSignal.order(created_at: :desc).first
        expect(last_signal).to be_present
        expect(last_signal.metadata['effective_timeframe']).to be_present
      end

      it 'skips trading context gate in exit_testing mode' do
        allow(Options::ChainAnalyzer).to receive(:pick_strikes_with_qualification).and_return([])

        expect(Context::Builder).not_to receive(:call)

        described_class.run_for(index_cfg)
      end

      it 'skips EntryQualityFilter in exit_testing mode' do
        allow(Options::ChainAnalyzer).to receive(:pick_strikes_with_qualification).and_return([])

        expect(Signal::EntryQualityFilter).not_to receive(:evaluate)

        described_class.run_for(index_cfg)
      end
    end
  end
end
