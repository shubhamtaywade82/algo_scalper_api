# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::ExpiryGate do
  let(:index_cfg) { { key: 'BANKNIFTY' } }

  def stub_nearest_expiry(date)
    analyzer = instance_double(Options::DerivativeChainAnalyzer, nearest_expiry: date&.strftime('%Y-%m-%d'))
    allow(Options::DerivativeChainAnalyzer).to receive(:new).with(index_key: 'BANKNIFTY').and_return(analyzer)
  end

  describe '.beyond_entry_window?' do
    before { allow(AlgoConfig).to receive(:fetch).and_return({ signals: { max_expiry_days: 7 } }) }

    it 'is true for a far-dated monthly expiry (21 days out)' do
      stub_nearest_expiry(21.days.from_now.to_date)

      expect(described_class.beyond_entry_window?(index_cfg)).to be true
    end

    it 'is false inside the window, including the boundary day' do
      stub_nearest_expiry(7.days.from_now.to_date)

      expect(described_class.beyond_entry_window?(index_cfg)).to be false
    end

    it 'does not block when the expiry cannot be resolved' do
      stub_nearest_expiry(nil)

      expect(described_class.beyond_entry_window?(index_cfg)).to be false
    end
  end

  describe '.max_expiry_days' do
    it 'defaults to 7 and honours signals.max_expiry_days' do
      allow(AlgoConfig).to receive(:fetch).and_return({})
      expect(described_class.max_expiry_days).to eq(7)

      allow(AlgoConfig).to receive(:fetch).and_return({ signals: { max_expiry_days: 3 } })
      expect(described_class.max_expiry_days).to eq(3)
    end
  end
end
