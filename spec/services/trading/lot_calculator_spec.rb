# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::LotCalculator do
  describe '.lot_size_for' do
    it 'returns fixed lot sizes' do
      expect(described_class.lot_size_for('NIFTY')).to eq(65)
      expect(described_class.lot_size_for(:sensex)).to eq(20)
    end

    it 'raises for unsupported symbols' do
      expect { described_class.lot_size_for('BANKNIFTY') }.to raise_error(
        Trading::LotCalculator::UnsupportedInstrumentError
      )
    end
  end
end
