# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine do
  describe '.resolve_nearest_expiry_date' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:expiry) { Date.new(2026, 4, 10) }

    it 'returns expiry from no_trade_gate when present' do
      out = described_class.send(
        :resolve_nearest_expiry_date,
        index_cfg: index_cfg,
        no_trade_gate: { expiry_date: expiry, chain_data: {} }
      )
      expect(out).to eq(expiry)
    end

    it 'falls back to DerivativeChainAnalyzer when expiry is nil' do
      analyzer = instance_double(Options::DerivativeChainAnalyzer, nearest_expiry: expiry)
      allow(Options::DerivativeChainAnalyzer).to receive(:new).with(index_key: 'NIFTY').and_return(analyzer)

      out = described_class.send(
        :resolve_nearest_expiry_date,
        index_cfg: index_cfg,
        no_trade_gate: { expiry_date: nil, chain_data: nil }
      )
      expect(out).to eq(expiry)
    end
  end

  describe '.entry_dte_guard_blocks?' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:today) { Date.new(2026, 4, 6) }

    before do
      allow(Time.zone).to receive(:today).and_return(today)
    end

    it 'returns false when guard disabled' do
      blocked = described_class.send(
        :entry_dte_guard_blocks?,
        index_cfg: index_cfg,
        signals_cfg: { entry_dte_guard: { enabled: false } },
        nearest_expiry: today + 1.day
      )
      expect(blocked).to be(false)
    end

    it 'returns true when DTE is at or below threshold' do
      blocked = described_class.send(
        :entry_dte_guard_blocks?,
        index_cfg: index_cfg,
        signals_cfg: {
          entry_dte_guard: { enabled: true, reject_when_days_to_expiry_lte: 1 }
        },
        nearest_expiry: today + 1.day
      )
      expect(blocked).to be(true)
    end

    it 'returns false when DTE is above threshold' do
      blocked = described_class.send(
        :entry_dte_guard_blocks?,
        index_cfg: index_cfg,
        signals_cfg: {
          entry_dte_guard: { enabled: true, reject_when_days_to_expiry_lte: 1 }
        },
        nearest_expiry: today + 3.days
      )
      expect(blocked).to be(false)
    end
  end

  describe '.run_for validation halt' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:instrument) { instance_double(Instrument) }
    let(:signals_cfg) do
      {
        halt_on_validation_failure: true,
        entry_strategy: { primary: 'supertrend' },
        enable_no_trade_engine: false
      }
    end

    let(:flow_result) do
      {
        direction: :bullish,
        primary_analysis: {
          supertrend: { last_value: 100.0 },
          adx_value: 20.0,
          last_candle_timestamp: Time.current
        },
        confirmation_analysis: nil,
        primary_series: instance_double(CandleSeries),
        ta_result: nil,
        regime_result: { regime: 'TRENDING_UP' },
        regime: 'TRENDING_UP',
        validation_result: { valid: false, reason: 'Failed checks: IV Rank' },
        effective_validation_mode: 'balanced'
      }
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(signals: signals_cfg)
      allow(described_class).to receive_messages(
        tradable_session?: true,
        fetch_instrument: instrument,
        initialize_analysis_context: {
          entry_primary: 'supertrend',
          primary_tf: '1m',
          enable_confirmation: false,
          confirmation_tf: nil
        },
        execute_supertrend_only_flow: flow_result,
        trading_context_blocked?: false,
        evaluate_entry_quality: { pass: true, score: 5, breakdown: {} }
      )
      allow(described_class).to receive(:execute_no_trade_gate).and_return({ expiry_date: nil, chain_data: nil })
      allow(Signal::StateTracker).to receive(:reset)
    end

    it 'stops before no-trade gate when comprehensive validation failed' do
      described_class.run_for(index_cfg)

      expect(described_class).not_to have_received(:execute_no_trade_gate)
      expect(Signal::StateTracker).to have_received(:reset).with('NIFTY')
    end
  end
end
