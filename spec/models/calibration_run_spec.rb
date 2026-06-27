# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalibrationRun do
  describe 'schema' do
    it 'has the expected columns' do
      cols = ActiveRecord::Base.connection.columns(:calibration_runs).map(&:name)
      expect(cols).to include(
        'symbol', 'weeks_analyzed', 'strike_mode',
        'raw_stats', 'proposed_patch',
        'is_regime_shift', 'regime_reason',
        'applied_at', 'applied_by',
        'created_at', 'updated_at'
      )
    end
  end

  describe 'validations' do
    it 'requires symbol' do
      run = described_class.new(weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
                                raw_stats: {}, proposed_patch: {})
      expect(run).not_to be_valid
      expect(run.errors[:symbol]).to be_present
    end
  end

  describe '#apply!' do
    let(:run) do
      described_class.create!(
        symbol: 'NIFTY',
        weeks_analyzed: 52,
        strike_mode: 'atm_plus_minus',
        raw_stats: { 'avg_gain' => 14.2 },
        proposed_patch: {
          'risk' => {
            'trailing' => { 'activation_pct' => 0.036, 'drawdown_pct' => 0.025 }
          }
        }
      )
    end

    it 'merges proposed_patch into algo_config_document' do
      run.apply!(applied_by: 'spec')

      config = AlgoConfig.fetch
      expect(config.dig(:risk, :trailing, :activation_pct)).to eq(0.036)
      expect(run.reload.applied_at).to be_present
      expect(run.applied_by).to eq('spec')
    end

    it 'raises when already applied' do
      run.apply!(applied_by: 'spec')

      expect { run.apply!(applied_by: 'spec') }.to raise_error('already applied')
    end
  end

  describe '#propose_config!' do
    it 'is a no-op when AlgoConfigVersion is undefined' do
      run = described_class.create!(
        symbol: 'NIFTY',
        weeks_analyzed: 52,
        strike_mode: 'atm_plus_minus',
        raw_stats: {},
        proposed_patch: { 'risk' => {} }
      )

      expect { run.propose_config! }.not_to raise_error
    end
  end
end
