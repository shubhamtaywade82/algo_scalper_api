# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig::ProfitabilitySlice2 do
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
        trading_time_restrictions: { enabled: false, avoid_periods: ['10:00-12:30'] },
        signals: { signal_tier: 'exploratory' }
      }.to_json
    )
    AlgoConfig.reset!
  end

  describe '.apply!' do
    it 'enables midday blackout and selective tier' do
      described_class.apply!

      config = AlgoConfig.fetch
      expect(config.dig(:trading_time_restrictions, :enabled)).to be(true)
      expect(config.dig(:trading_time_restrictions, :avoid_periods)).to eq(['11:00-13:45'])
      expect(config.dig(:signals, :signal_tier)).to eq('selective')
    end
  end

  describe '.rollback!' do
    it 'disables blackout and restores exploratory tier' do
      described_class.apply!
      described_class.rollback!

      config = AlgoConfig.fetch
      expect(config.dig(:trading_time_restrictions, :enabled)).to be(false)
      expect(config.dig(:signals, :signal_tier)).to eq('exploratory')
    end
  end
end
