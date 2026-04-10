# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine do
  describe '.execute_no_trade_gate' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:instrument) { instance_double(Instrument) }
    let(:series_1m) { instance_double(CandleSeries, candles: Array.new(20) { build(:candle) }) }
    let(:series_5m) { instance_double(CandleSeries, candles: Array.new(20) { build(:candle) }) }
    let(:expiry_date) { Date.new(2026, 4, 9) }
    let(:chain_data) { { oc: {} } }
    let(:context) { instance_double(OpenStruct) }
    let(:signals_cfg) { { enable_no_trade_engine: true } }
    let(:derivative_analyzer) { instance_double(Options::DerivativeChainAnalyzer, nearest_expiry: expiry_date) }

    before do
      allow(instrument).to receive(:candle_series).with(interval: '1').and_return(series_1m)
      allow(instrument).to receive(:candle_series).with(interval: '5').and_return(series_5m)
      allow(Options::DerivativeChainAnalyzer).to receive(:new).with(index_key: 'NIFTY').and_return(derivative_analyzer)
      allow(instrument).to receive(:fetch_option_chain).with(expiry_date).and_return(chain_data)
      allow(Entries::NoTradeContextBuilder).to receive(:build).and_return(context)
      allow(Signal::StateTracker).to receive(:reset)
    end

    it 'blocks the signal flow when the no-trade engine rejects the setup' do
      result = instance_double(Entries::NoTradeEngine::Result, allowed: false, score: 3.0, reasons: ['Weak trend'])
      allow(Entries::NoTradeEngine).to receive(:validate).with(context).and_return(result)

      gate = described_class.send(
        :execute_no_trade_gate,
        index_cfg: index_cfg,
        instrument: instrument,
        signals_cfg: signals_cfg
      )

      expect(gate).to be_nil
      expect(Signal::StateTracker).to have_received(:reset).with('NIFTY')
    end

    it 'returns the fetched expiry and chain data when the setup is allowed' do
      result = instance_double(Entries::NoTradeEngine::Result, allowed: true, score: 1.5, reasons: [])
      allow(Entries::NoTradeEngine).to receive(:validate).with(context).and_return(result)

      gate = described_class.send(
        :execute_no_trade_gate,
        index_cfg: index_cfg,
        instrument: instrument,
        signals_cfg: signals_cfg
      )

      expect(gate).to eq(expiry_date: expiry_date, chain_data: chain_data)
      expect(Signal::StateTracker).not_to have_received(:reset)
    end

    it 'blocks when there is not enough 1m/5m context to evaluate safely' do
      allow(instrument).to receive(:candle_series).with(interval: '1').and_return(instance_double(CandleSeries, candles: Array.new(8) { build(:candle) }))

      gate = described_class.send(
        :execute_no_trade_gate,
        index_cfg: index_cfg,
        instrument: instrument,
        signals_cfg: signals_cfg
      )

      expect(gate).to be_nil
      expect(Entries::NoTradeContextBuilder).not_to have_received(:build)
      expect(Signal::StateTracker).to have_received(:reset).with('NIFTY')
    end
  end

  describe '.run_for' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:instrument) { instance_double(Instrument) }
    let(:signals_cfg) { { entry_strategy: {}, enable_no_trade_engine: true } }
    let(:analysis_result) do
      {
        direction: :bullish,
        primary_analysis: {
          supertrend: { last_value: 24_500.0 },
          adx_value: 28.0,
          last_candle_timestamp: Time.current
        },
        confirmation_analysis: nil,
        primary_series: instance_double(CandleSeries),
        ta_result: nil,
        regime_result: { regime: 'TRENDING_UP' },
        regime: 'TRENDING_UP',
        validation_result: {},
        effective_validation_mode: 'conservative',
        effective_timeframe: '5m',
        strategy_recommendation: nil,
        use_strategy_recommendations: false
      }
    end

    before do
      allow(described_class).to receive_messages(
        tradable_session?: true,
        fetch_instrument: instrument,
        initialize_analysis_context: {
          entry_primary: '',
          primary_tf: '5m',
          enable_confirmation: false,
          confirmation_tf: nil
        },
        execute_standard_analysis_flow: analysis_result,
        trading_context_blocked?: false,
        evaluate_entry_quality: { pass: true, score: 4, breakdown: {} }
      )
      allow(AlgoConfig).to receive(:fetch).and_return(signals: signals_cfg)
      allow(described_class).to receive(:execute_execution_gates)
    end

    it 'stops before execution gates when the no-trade gate blocks the setup' do
      allow(described_class).to receive(:execute_no_trade_gate).and_return(nil)

      described_class.run_for(index_cfg)

      expect(described_class).not_to have_received(:execute_execution_gates)
    end
  end
end
