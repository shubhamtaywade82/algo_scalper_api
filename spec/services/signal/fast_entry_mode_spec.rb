# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::FastEntryMode do
  after do
    described_class.instance_variable_set(:@enabled, nil)
    described_class.instance_variable_set(:@cached_at, nil)
    described_class.instance_variable_set(:@logged, nil)
  end

  describe '.enabled?' do
    context 'when config enables fast entry' do
      before do
        allow(ENV).to receive(:fetch).with('FAST_ENTRY_MODE', nil).and_return(nil)
        allow(AlgoConfig).to receive(:fetch).and_return({ signals: { fast_entry_mode: { enabled: true } } })
      end

      it 'returns true' do
        expect(described_class.enabled?).to be true
      end
    end

    context 'when FAST_ENTRY_MODE env is set' do
      before do
        allow(ENV).to receive(:fetch).with('FAST_ENTRY_MODE', nil).and_return('true')
      end

      it 'returns true regardless of config' do
        allow(AlgoConfig).to receive(:fetch).and_return({ signals: { fast_entry_mode: { enabled: false } } })

        expect(described_class.enabled?).to be true
      end
    end
  end

  describe '.effective_momentum_score' do
    it 'returns max momentum when fast entry is enabled' do
      allow(described_class).to receive(:enabled?).and_return(true)

      expect(described_class.effective_momentum_score(1)).to eq(3)
    end

    it 'returns raw score when fast entry is disabled' do
      allow(described_class).to receive(:enabled?).and_return(false)

      expect(described_class.effective_momentum_score(1)).to eq(1)
    end
  end
end
