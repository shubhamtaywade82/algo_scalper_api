# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::ATRCompressionChecker do
  let(:instrument) { instance_double(Instrument, symbol_name: 'NIFTY', security_id: '13') }

  before do
    allow(OptionsBuying::Mode).to receive(:compression_enabled?).and_return(true)
    allow(OptionsBuying::Mode).to receive(:config).and_return(
      atr_compression: { max_setup_ratio: 0.30, atr_period: 14 }
    )
    allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'NIFTY', sid: '13' }])
  end

  describe '.compressed?' do
    it 'returns true when setup ratio is below threshold' do
      allow_any_instance_of(described_class).to receive(:setup_ratio).and_return(0.20)

      expect(described_class.compressed?(instrument)).to be(true)
    end

    it 'returns false when setup ratio is above threshold' do
      allow_any_instance_of(described_class).to receive(:setup_ratio).and_return(0.50)

      expect(described_class.compressed?(instrument)).to be(false)
    end
  end
end
