# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig::DocumentStore do
  let(:doc_key) { described_class::DOCUMENT_KEY }

  after do
    Setting.where(key: doc_key).delete_all
    Setting.where(key: described_class::LEGACY_OVERRIDES_KEY).delete_all
    AlgoConfigChangeLog.delete_all
    AlgoConfig.reset!
  end

  describe '.current_mutable_document' do
    before do
      Setting.put(doc_key, { mode: 'paper', risk: { sl_pct: 0.02 } }.to_json)
      AlgoConfig.reset!
    end

    it 'returns a deep copy that callers can mutate safely' do
      doc1 = described_class.current_mutable_document
      doc1[:risk][:sl_pct] = 999
      doc2 = described_class.current_mutable_document
      expect(doc2[:risk][:sl_pct]).to eq(0.02)
    end

    it 'bootstraps from YAML when no document exists' do
      Setting.where(key: doc_key).delete_all
      AlgoConfig.reset!

      doc = described_class.current_mutable_document
      expect(doc).to be_a(Hash)
      expect(doc.keys).not_to be_empty
    end
  end

  describe '.apply_top_level_replacements!' do
    before do
      Setting.put(doc_key, { mode: 'paper', risk: { a: 1 }, signals: { b: 2 } }.to_json)
      AlgoConfig.reset!
    end

    it 'replaces only present top-level subtrees' do
      described_class.apply_top_level_replacements!(
        { risk: { c: 3 } },
        source: 'test',
        actor: 'rspec'
      )
      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc['risk']).to eq('c' => 3)
      expect(doc['signals']).to eq('b' => 2)
    end

    it 'redacts sensitive keys in audit patch' do
      described_class.apply_top_level_replacements!(
        { telegram: { bot_token: 'secret', chat_id: 1 } },
        source: 'test',
        actor: 'rspec'
      )
      log = AlgoConfigChangeLog.order(:id).last
      expect(log.patch['replace']['telegram']['bot_token']).to eq('[REDACTED]')
      expect(log.patch['replace']['telegram']['chat_id']).to eq(1)
    end

    it 'rejects non-Hash argument' do
      expect { described_class.apply_top_level_replacements!('bad', source: 'test') }
        .to raise_error(ArgumentError, /must be a Hash/)
    end

    it 'no-ops for empty replacements' do
      expect { described_class.apply_top_level_replacements!({}, source: 'test') }
        .not_to change(AlgoConfigChangeLog, :count)
    end

    it 'resets AlgoConfig in-process cache' do
      allow(AlgoConfig).to receive(:reset!)
      described_class.apply_top_level_replacements!(
        { risk: { c: 3 } },
        source: 'test'
      )
      expect(AlgoConfig).to have_received(:reset!)
    end
  end

  describe '.apply_deep_merge_patch!' do
    before do
      Setting.put(doc_key, { mode: 'paper', risk: { trailing: { drawdown_pct: 0.01 } } }.to_json)
      AlgoConfig.reset!
    end

    it 'deep-merges nested keys' do
      described_class.apply_deep_merge_patch!(
        { 'risk' => { 'trailing' => { 'activation_pct' => 0.05 } } },
        source: 'test',
        actor: 'rspec'
      )
      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc.dig('risk', 'trailing', 'drawdown_pct')).to eq(0.01)
      expect(doc.dig('risk', 'trailing', 'activation_pct')).to eq(0.05)
    end

    it 'rejects non-Hash argument' do
      expect { described_class.apply_deep_merge_patch!([], source: 'test') }
        .to raise_error(ArgumentError, /must be a Hash/)
    end

    it 'rejects an out-of-range gate value without persisting' do
      expect do
        described_class.apply_deep_merge_patch!(
          { entry_quality: { gates: { min_adx: -5 } } },
          source: 'test'
        )
      end.to raise_error(AlgoConfig::ValidationError, /min_adx/)

      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc.dig('entry_quality', 'gates', 'min_adx')).to be_nil
    end

    it 'does not write a change log when validation fails' do
      expect do
        expect do
          described_class.apply_deep_merge_patch!(
            { signals: { signal_tier: 'wild' } },
            source: 'test'
          )
        end.to raise_error(AlgoConfig::ValidationError)
      end.not_to change(AlgoConfigChangeLog, :count)
    end
  end

  describe '.force_bootstrap!' do
    before do
      Setting.put(doc_key, { stale: true }.to_json)
      AlgoConfig.reset!
    end

    it 're-seeds from YAML and logs the change' do
      doc = described_class.force_bootstrap!
      expect(doc).to be_a(Hash)
      expect(doc.keys).not_to be_empty
      log = AlgoConfigChangeLog.order(:id).last
      expect(log.source).to eq('rake_bootstrap_document')
    end
  end
end
