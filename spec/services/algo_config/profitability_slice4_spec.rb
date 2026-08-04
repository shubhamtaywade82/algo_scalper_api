# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig::ProfitabilitySlice4 do
  let(:doc_key) { AlgoConfig::DocumentStore::DOCUMENT_KEY }

  after do
    Setting.where(key: doc_key).delete_all
    AlgoConfigChangeLog.delete_all
    AlgoConfig.reset!
  end

  before do
    Setting.put(
      doc_key,
      {
        risk: {
          sl_pct: 0.10,
          adaptive_trailing: {
            enabled: true,
            stages: [
              { name: 'entry_guard', min_profit: 0.0, trail_behind_peak: 0.40, hard_stop: -0.30 },
              { name: 'momentum_ride', min_profit: 0.20, trail_behind_peak: 0.35, hard_stop: nil }
            ]
          }
        }
      }.to_json
    )
    AlgoConfig.reset!
  end

  describe '.apply!' do
    it 'tightens sl_pct and entry_guard hard_stop' do
      described_class.apply!

      config = AlgoConfig.fetch
      expect(config.dig(:risk, :sl_pct)).to eq(0.08)

      entry_guard = config.dig(:risk, :adaptive_trailing, :stages)
                          .find { |s| s[:name] == 'entry_guard' }
      expect(entry_guard[:hard_stop]).to eq(-0.08)
    end
  end

  describe '.rollback!' do
    it 'restores sl_pct and entry_guard hard_stop' do
      described_class.apply!
      described_class.rollback!

      config = AlgoConfig.fetch
      expect(config.dig(:risk, :sl_pct)).to eq(0.10)

      entry_guard = config.dig(:risk, :adaptive_trailing, :stages)
                          .find { |s| s[:name] == 'entry_guard' }
      expect(entry_guard[:hard_stop]).to eq(-0.30)
    end
  end

  describe '.status' do
    it 'reports tightened values after apply' do
      described_class.apply!

      expect(described_class.status).to eq(
        sl_pct: 0.08,
        entry_guard_hard_stop: -0.08
      )
    end
  end
end
