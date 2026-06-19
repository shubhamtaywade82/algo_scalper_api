# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig::Audit do
  let(:doc_key) { AlgoConfig::DocumentStore::DOCUMENT_KEY }

  after do
    Setting.where(key: doc_key).delete_all
    Setting.where(key: described_class::LEGACY_OVERRIDES_KEY).delete_all
    Setting.where(key: described_class::LEGACY_ARCHIVED_KEY).delete_all
    Setting.where(key: AlgoConfig::TIER_PRESETS_SETTING_KEY).delete_all
    Setting.where(key: AlgoConfig::REGISTRY_SETTING_KEY).delete_all
    AlgoConfigChangeLog.delete_all
    AlgoConfig.reset!
  end

  describe '.run' do
    it 'reports missing document when not bootstrapped' do
      report = described_class.run
      expect(report.document_present).to be(false)
      expect(report.missing_in_document).not_to be_empty
    end

    context 'when document exists' do
      before do
        Setting.put(doc_key, { risk: { sl_pct: 0.02 }, signals: { signal_tier: 'standard' } }.to_json)
      end

      it 'reports document metadata' do
        report = described_class.run
        expect(report.document_present).to be(true)
        expect(report.document_top_level_keys).to include(:risk, :signals)
      end
    end
  end

  describe '.verify_canonical!' do
    it 'raises when document is missing' do
      expect { described_class.verify_canonical! }.to raise_error(StandardError, /algo_config_document missing/)
    end
  end
end
