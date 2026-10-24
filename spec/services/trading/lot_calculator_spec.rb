# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::LotCalculator do
  describe '.lot_size_for' do
    it 'returns configured lot sizes for supported indices' do
      expect(described_class.lot_size_for('NIFTY')).to eq(75)
      expect(described_class.lot_size_for('BANKNIFTY')).to eq(15)
      expect(described_class.lot_size_for(:sensex)).to eq(10)
    end

    it 'raises for unsupported symbols' do
      expect { described_class.lot_size_for('UNKNOWN_INDEX') }.to raise_error(
        Trading::LotCalculator::UnsupportedInstrumentError
      )
    end
  end
end
