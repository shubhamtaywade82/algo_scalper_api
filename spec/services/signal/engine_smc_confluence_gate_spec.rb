# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine do
  describe '.execute_execution_gates' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:primary_series) { instance_double(CandleSeries) }
    let(:instrument) { instance_double(Instrument) }

    before do
      allow(Entries::EntryFilterEngine).to receive(:new).and_return(instance_double(Entries::EntryFilterEngine, valid_entry?: true))
      allow(Trading::PermissionResolver).to receive(:resolve).and_return(:scale_ready)
      allow(Signal::MomentumValidator).to receive(:validate).and_return(double(score: 2))
    end

    context 'when enable_smc_confluence_gating is true' do
      let(:signals_cfg) do
        {
          enable_smc_avrz_permission: false,
          enable_smc_decision_alignment: false,
          enable_smc_confluence_gating: true,
          enable_smc_confluence_digest: false
        }
      end

      it 'returns nil when bullish but LTF long_signal is false' do
        fake_last = instance_double(Smc::Confluence::BarResult, long_signal: false, short_signal: false)
        allow(Smc::Confluence::LtfSnapshot).to receive(:fetch).and_return({ last: fake_last, summary: nil })

        result = described_class.send(
          :execute_execution_gates,
          index_cfg,
          instrument,
          primary_series,
          :bullish,
          signals_cfg
        )
        expect(result).to be_nil
      end

      it 'returns gate hash when bullish and LTF long_signal is true' do
        fake_last = instance_double(Smc::Confluence::BarResult, long_signal: true, short_signal: false)
        allow(Smc::Confluence::LtfSnapshot).to receive(:fetch).and_return({ last: fake_last, summary: nil })

        result = described_class.send(
          :execute_execution_gates,
          index_cfg,
          instrument,
          primary_series,
          :bullish,
          signals_cfg
        )
        expect(result).to be_a(Hash)
        expect(result[:permission]).to eq(:scale_ready)
        expect(result[:smc_confluence_ltf_summary]).to be_nil
      end
    end

    context 'when enable_smc_confluence_digest is true' do
      let(:signals_cfg) do
        {
          enable_smc_avrz_permission: false,
          enable_smc_decision_alignment: false,
          enable_smc_confluence_gating: false,
          enable_smc_confluence_digest: true
        }
      end

      it 'includes smc_confluence_ltf_summary from snapshot' do
        summary = { 'long_score' => 2, 'short_score' => 1 }
        allow(Smc::Confluence::LtfSnapshot).to receive(:fetch).and_return(
          { last: nil, summary: summary }
        )

        result = described_class.send(
          :execute_execution_gates,
          index_cfg,
          instrument,
          primary_series,
          :bearish,
          signals_cfg
        )
        expect(result[:smc_confluence_ltf_summary]).to eq(summary)
      end
    end
  end
end
