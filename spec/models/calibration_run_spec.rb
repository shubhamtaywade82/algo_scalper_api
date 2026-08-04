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
      rec = described_class.new(weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
                                raw_stats: {}, proposed_patch: {})
      expect(rec).not_to be_valid
      expect(rec.errors[:symbol]).to be_present
    end
  end

  describe '#apply!' do
    let(:doc_key) { AlgoConfig::DocumentStore::DOCUMENT_KEY }

    before do
      Setting.put(doc_key, { mode: 'paper', risk: { some_other_key: 0.9 } }.to_json)
      AlgoConfig.reset!
    end

    after do
      Setting.where(key: doc_key).delete_all
      AlgoConfigChangeLog.delete_all
      AlgoConfig.reset!
    end

    it 'writes merged patch into algo_config_document' do
      expect { run.apply! }.to change(AlgoConfigChangeLog, :count).by(1)
      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc.dig('risk', 'some_other_key')).to eq(0.9)
      expect(doc.dig('risk', 'percentage_pnl_exit', 'target_pct')).to eq(0.064)
    end

    it 'records calibration_apply audit with run id' do
      run.apply!
      log = AlgoConfigChangeLog.order(:id).last
      expect(log.source).to eq('calibration_apply')
      expect(log.metadata['calibration_run_id']).to eq(run.id)
    end

      config = AlgoConfig.fetch
      expect(config.dig(:risk, :trailing, :activation_pct)).to eq(0.036)
      expect(run.reload.applied_at).to be_present
      expect(run.applied_by).to eq('spec')
    end

    it 'raises when already applied' do
      run.apply!(applied_by: 'spec')

    it 'raises on double-apply' do
      run.update!(applied_at: Time.current)
      expect { run.apply! }.to raise_error(RuntimeError, /already applied/)
    end

    it 'deep-merges proposed_patch over existing document' do
      run2 = described_class.create!(
        symbol: 'NIFTY', weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
        raw_stats: {}, proposed_patch: { 'risk' => { 'new_key' => 0.1 } }
      )
      run2.apply!

      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc.dig('risk', 'some_other_key')).to eq(0.9)
      expect(doc.dig('risk', 'new_key')).to eq(0.1)
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
