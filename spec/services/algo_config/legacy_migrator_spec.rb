# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig::LegacyMigrator do
  let(:doc_key) { AlgoConfig::DocumentStore::DOCUMENT_KEY }
  let(:legacy_key) { described_class::LEGACY_KEY }

  after do
    Setting.where(key: doc_key).delete_all
    Setting.where(key: legacy_key).delete_all
    Setting.where(key: described_class::ARCHIVED_KEY).delete_all
    AlgoConfigChangeLog.delete_all
    AlgoConfig.reset!
  end

  describe '.migrate!' do
    it 'skips when no legacy overrides exist' do
      expect(described_class.migrate!).to eq(:skipped_no_legacy)
    end

    it 'merges legacy into document and archives legacy key' do
      Setting.put(doc_key, { risk: { sl_pct: 0.02 } }.to_json)
      Setting.put(legacy_key, { risk: { tp_pct: 0.12 } }.to_json)
      AlgoConfig.reset!

      expect(described_class.migrate!).to eq(:migrated)

      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc.dig('risk', 'sl_pct').to_f).to eq(0.02)
      expect(doc.dig('risk', 'tp_pct').to_f).to eq(0.12)
      expect(Setting.find_by(key: legacy_key)).to be_nil
      expect(Setting.find_by(key: described_class::ARCHIVED_KEY)).to be_present
    end
  end
end
