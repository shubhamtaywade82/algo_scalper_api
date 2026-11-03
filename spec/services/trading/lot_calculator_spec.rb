# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::LotCalculator do
  describe '.lot_size_for' do
    def option_contract(expiry_date:, lot_size:)
      create(:instrument, underlying_symbol: 'NIFTY', instrument_type: 'OPTIDX', option_type: 'CE',
                          strike_price: 23_000, expiry_date: expiry_date, lot_size: lot_size)
    end

    it 'returns the lot size of the nearest live contract from the instrument master' do
      option_contract(expiry_date: 2.weeks.from_now.to_date, lot_size: 75)
      option_contract(expiry_date: 3.days.from_now.to_date, lot_size: 65)
      option_contract(expiry_date: 3.days.ago.to_date, lot_size: 50)

      expect(described_class.lot_size_for(:nifty)).to eq(65)
    end

    it 'raises for unsupported symbols' do
      expect { described_class.lot_size_for('UNKNOWN_INDEX') }.to raise_error(
        Trading::LotCalculator::UnsupportedInstrumentError
      )
    end
  end
end
