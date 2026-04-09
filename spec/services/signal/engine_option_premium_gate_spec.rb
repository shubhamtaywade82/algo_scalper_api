# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine do
  describe '.execute_entry_gate' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:instrument) { instance_double(Instrument) }
    let(:signal) { instance_double(TradingSignal, record_entry_outcome: nil) }
    let(:primary_series) { instance_double(CandleSeries) }
    let(:options_analysis) do
      {
        expiry_blocked: false,
        expiry_date: Date.new(2026, 4, 9),
        chain_data: { oc: {} },
        iv_rank: { ok: true },
        theta_risk: { ok: true }
      }
    end
    let(:pick) { { symbol: 'NIFTYAPR25000CE', ltp: 118.0, prev_close: 100.0, strike: 25_000.0 } }

    before do
      allow(primary_series).to receive(:atr).with(14).and_return(120.0)
      allow(Options::ChainAnalyzer).to receive(:pick_strikes_with_qualification).and_return([pick])
      allow(described_class).to receive_messages(
        evaluate_market_context_for_entry: [{}, false],
        options_analysis_gate_blocks_entry?: false
      )
      allow(Signal::StateTracker).to receive(:reset)
      merged = AlgoConfig.fetch.deep_dup
      merged[:signals] = (merged[:signals] || {}).merge(enable_option_premium_momentum_gate: true)
      allow(AlgoConfig).to receive(:fetch).and_return(merged)
    end

    it 'blocks when the selected option premium momentum fails validation' do
      allow(Signal::MomentumValidator).to receive(:validate_option_pick).and_return(
        { confirms: false, reason: 'Option premium speed 3.0% < 8.0% threshold' }
      )

      result = described_class.send(
        :execute_entry_gate,
        index_cfg: index_cfg,
        instrument: instrument,
        signal: signal,
        final_direction: :bullish,
        primary_series: primary_series,
        options_analysis: options_analysis,
        momentum_score: 2,
        permission: :scale_ready,
        smc_decision: :call
      )

      expect(result).to be_nil
      expect(signal).to have_received(:record_entry_outcome).with('skipped', 'option premium momentum')
      expect(Signal::StateTracker).to have_received(:reset).with('NIFTY')
    end

    it 'continues when the selected option premium momentum confirms' do
      allow(Signal::MomentumValidator).to receive(:validate_option_pick).and_return(
        { confirms: true, reason: 'Option premium speed 18.0% >= 8.0% threshold' }
      )

      result = described_class.send(
        :execute_entry_gate,
        index_cfg: index_cfg,
        instrument: instrument,
        signal: signal,
        final_direction: :bullish,
        primary_series: primary_series,
        options_analysis: options_analysis,
        momentum_score: 2,
        permission: :scale_ready,
        smc_decision: :call
      )

      expect(result).to include(picks: [pick], execution_permission: :scale_ready)
    end

    it 'skips premium validation when enable_option_premium_momentum_gate is false' do
      merged = AlgoConfig.fetch.deep_dup
      merged[:signals] = (merged[:signals] || {}).merge(enable_option_premium_momentum_gate: false)
      allow(AlgoConfig).to receive(:fetch).and_return(merged)
      allow(Signal::MomentumValidator).to receive(:validate_option_pick).and_raise('should not run')

      result = described_class.send(
        :execute_entry_gate,
        index_cfg: index_cfg,
        instrument: instrument,
        signal: signal,
        final_direction: :bullish,
        primary_series: primary_series,
        options_analysis: options_analysis,
        momentum_score: 2,
        permission: :scale_ready,
        smc_decision: :call
      )

      expect(result).to include(picks: [pick], execution_permission: :scale_ready)
    end
  end
end
