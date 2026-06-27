# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig::ProfitabilitySlice3 do
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
        indices: [
          { key: 'NIFTY', trade_limits: { max_trades_per_day: 2 } },
          { key: 'SENSEX', trade_limits: { max_trades_per_day: 2 } }
        ]
      }.to_json
    )
    AlgoConfig.reset!
  end

  describe '.apply!' do
    it 'pauses SENSEX via max_trades_per_day=0' do
      described_class.apply!

      sensex = AlgoConfig.fetch[:indices].find { |idx| idx[:key] == 'SENSEX' }
      expect(sensex.dig(:trade_limits, :max_trades_per_day)).to eq(0)
    end
  end

  describe '.rollback!' do
    it 'restores SENSEX trade limit' do
      described_class.apply!
      described_class.rollback!

      sensex = AlgoConfig.fetch[:indices].find { |idx| idx[:key] == 'SENSEX' }
      expect(sensex.dig(:trade_limits, :max_trades_per_day)).to eq(2)
    end
  end

  describe '.status' do
    it 'reports paused state after apply' do
      described_class.apply!

      expect(described_class.status).to eq(
        sensex_max_trades_per_day: 0,
        sensex_paused: true
      )
    end
  end
end
