# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Calibration::ConfigApplier do
  let(:symbol) { 'NIFTY' }
  let(:parsed_result) do
    {
      diagnosis: { 'primary_failure' => 'SL noise' },
      parameter_changes: [{ 'parameter' => 'sl_pct', 'suggested' => 0.12 }],
      proposed_patch: { 'risk' => { 'sl_pct' => 0.12 } },
      regime_rules: [{ 'regime' => 'trend', 'action' => 'disable_entries', 'reason' => 'test' }]
    }
  end

  let(:validation_result) do
    {
      approved: true,
      baseline_pnl: 1000,
      projected_pnl: 1200,
      baseline_metrics: {},
      projected_metrics: {}
    }
  end

  let(:dataset_meta) { { total_trades: 25, win_rate: 60.0 } }

  describe '.call' do
    it 'creates a CalibrationRun record' do
      expect {
        described_class.call(
          symbol: symbol,
          parsed_result: parsed_result,
          validation_result: validation_result,
          dataset_meta: dataset_meta
        )
      }.to change(CalibrationRun, :count).by(1)

      run = CalibrationRun.last
      expect(run.symbol).to eq('NIFTY')
      expect(run.proposed_patch['risk']['sl_pct']).to eq(0.12)
      expect(run.is_regime_shift).to be true
      expect(run.regime_reason).to include('Disable entries in trend')
    end

    it 'does Not create if patch is blank' do
      parsed_result[:proposed_patch] = {}
      expect {
        described_class.call(
          symbol: symbol,
          parsed_result: parsed_result,
          validation_result: validation_result,
          dataset_meta: dataset_meta
        )
      }.not_to change(CalibrationRun, :count)
    end
  end
end
