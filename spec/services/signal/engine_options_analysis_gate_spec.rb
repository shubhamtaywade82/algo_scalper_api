# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine do
  describe '.options_analysis_gate_blocks_entry?' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:signal) { instance_double(TradingSignal) }

    before do
      allow(signal).to receive(:record_entry_outcome)
      allow(Signal::StateTracker).to receive(:reset)
    end

    context 'when options_analysis_gate is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(signals: { options_analysis_gate: { enabled: false } })
      end

      it 'returns false' do
        blocked = described_class.send(
          :options_analysis_gate_blocks_entry?,
          signal: signal,
          index_cfg: index_cfg,
          options_analysis: { iv_rank: { valid: false }, theta_risk: { valid: false } }
        )
        expect(blocked).to be(false)
        expect(signal).not_to have_received(:record_entry_outcome)
      end
    end

    context 'when gate is enabled and IV rank fails' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          signals: {
            options_analysis_gate: {
              enabled: true,
              block_on_iv_rank_failure: true,
              block_on_theta_risk_failure: true
            }
          }
        )
      end

      it 'returns true and records skip' do
        blocked = described_class.send(
          :options_analysis_gate_blocks_entry?,
          signal: signal,
          index_cfg: index_cfg,
          options_analysis: {
            iv_rank: { valid: false, name: 'IV Rank', message: 'Extreme volatility' },
            theta_risk: { valid: true, name: 'Theta Risk', message: 'Low theta risk' }
          }
        )
        expect(blocked).to be(true)
        expect(signal).to have_received(:record_entry_outcome).with(
          'skipped',
          'options_analysis_iv_rank: IV Rank — Extreme volatility',
          extra_metadata: { 'entry_skip_stage' => 'options_analysis', 'entry_skip_code' => 'iv_rank_failure' }
        )
        expect(Signal::StateTracker).to have_received(:reset).with('NIFTY')
      end
    end

    context 'when gate is enabled and theta risk fails' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          signals: {
            options_analysis_gate: {
              enabled: true,
              block_on_iv_rank_failure: true,
              block_on_theta_risk_failure: true
            }
          }
        )
      end

      it 'returns true and records skip' do
        blocked = described_class.send(
          :options_analysis_gate_blocks_entry?,
          signal: signal,
          index_cfg: index_cfg,
          options_analysis: {
            iv_rank: { valid: true, name: 'IV Rank', message: 'OK' },
            theta_risk: { valid: false, name: 'Theta Risk', message: 'Too close to close' }
          }
        )
        expect(blocked).to be(true)
        expect(signal).to have_received(:record_entry_outcome).with(
          'skipped',
          'options_analysis_theta_risk: Theta Risk — Too close to close',
          extra_metadata: { 'entry_skip_stage' => 'options_analysis', 'entry_skip_code' => 'theta_risk_failure' }
        )
      end
    end

    context 'when gate is enabled and checks pass' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          signals: { options_analysis_gate: { enabled: true } }
        )
      end

      it 'returns false' do
        blocked = described_class.send(
          :options_analysis_gate_blocks_entry?,
          signal: signal,
          index_cfg: index_cfg,
          options_analysis: {
            iv_rank: { valid: true, name: 'IV Rank', message: 'OK' },
            theta_risk: { valid: true, name: 'Theta Risk', message: 'OK' }
          }
        )
        expect(blocked).to be(false)
        expect(signal).not_to have_received(:record_entry_outcome)
      end
    end
  end
end
