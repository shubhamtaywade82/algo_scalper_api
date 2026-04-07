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
  end
end
