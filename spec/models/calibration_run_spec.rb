# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalibrationRun do
  let(:run) do
    described_class.create!(
      symbol: 'NIFTY',
      weeks_analyzed: 52,
      strike_mode: 'atm_plus_minus',
      raw_stats: { 'avg_gain' => 14.2, 'avg_retrace_abs' => 3.1 },
      proposed_patch: {
        'risk' => {
          'percentage_pnl_exit' => { 'target_pct' => 0.064 },
          'trailing' => { 'activation_pct' => 0.036, 'drawdown_pct' => 0.025 }
        }
      }
    )
  end

  describe 'schema' do
    it 'has the expected columns' do
      cols = ActiveRecord::Base.connection.columns(:calibration_runs).map(&:name)
      expect(cols).to include('symbol', 'raw_stats', 'proposed_patch', 'applied_at')
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
    before do
      allow(Setting).to receive(:put)
      allow(Setting).to receive(:find_by).and_return(nil)
      allow(AlgoConfig).to receive(:reset!)
    end

    it 'writes merged patch via Setting.put' do
      run.apply!
      expect(Setting).to have_received(:put).with('algo_config_overrides', anything)
    end

    it 'calls AlgoConfig.reset! to bust in-process cache' do
      run.apply!
      expect(AlgoConfig).to have_received(:reset!)
    end

    it 'sets applied_at' do
      run.apply!
      expect(run.reload.applied_at).to be_present
    end

    it 'sets applied_by from argument' do
      run.apply!(applied_by: 'telegram')
      expect(run.reload.applied_by).to eq('telegram')
    end

    it 'raises on double-apply' do
      run.update!(applied_at: Time.current)
      expect { run.apply! }.to raise_error(RuntimeError, /already applied/)
    end

    it 'deep-merges proposed_patch over existing overrides' do
      existing = { 'risk' => { 'some_other_key' => 0.9 } }.to_json
      captured = nil
      allow(Setting).to receive(:find_by).and_return(
        instance_double(Setting, value: existing)
      )
      allow(Setting).to receive(:put) { |_k, v| captured = v }

      run2 = described_class.create!(
        symbol: 'NIFTY', weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
        raw_stats: {}, proposed_patch: { 'risk' => { 'new_key' => 0.1 } }
      )
      run2.apply!

      merged = JSON.parse(captured)
      expect(merged.dig('risk', 'some_other_key')).to eq(0.9)
      expect(merged.dig('risk', 'new_key')).to eq(0.1)
    end
  end

  describe '#propose_config!' do
    it 'is a no-op when AlgoConfigVersion is not defined' do
      hide_const('AlgoConfigVersion') if defined?(AlgoConfigVersion)
      expect { run.propose_config! }.not_to raise_error
    end
  end
end
