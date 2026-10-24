# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Quantity do
  describe '.resolve!' do
    it 'accepts positive integers' do
      expect(described_class.resolve!(7)).to eq(7)
    end

    it 'accepts integer strings from broker/config payloads' do
      expect(described_class.resolve!('7')).to eq(7)
    end

    it 'accepts whole-number floats and decimal strings' do
      expect(described_class.resolve!(7.0)).to eq(7)
      expect(described_class.resolve!('7.0')).to eq(7)
      expect(described_class.resolve!(BigDecimal('75'))).to eq(75)
    end

    it 'rejects nil, blanks, zero and negatives' do
      [nil, '', 0, '0', -5, '-5'].each do |bad|
        expect { described_class.resolve!(bad) }.to raise_error(Errors::InvalidQuantity, /quantity must be a positive whole number/)
      end
    end

    it 'rejects fractional and garbage values' do
      [2.5, '2.5', 'abc', '7abc', Float::NAN, Float::INFINITY, {}, []].each do |bad|
        expect { described_class.resolve!(bad) }.to raise_error(Errors::InvalidQuantity)
      end
    end

    it 'includes the caller context in the message' do
      expect { described_class.resolve!(nil, context: 'NIFTY buy_option!') }
        .to raise_error(Errors::InvalidQuantity, /NIFTY buy_option!/)
    end
  end

  describe '.resolve (non-raising)' do
    it 'returns the quantity when valid' do
      expect(described_class.resolve('50')).to eq(50)
    end

    it 'returns nil (never zero) when unresolvable' do
      [nil, 0, 'abc', 2.5].each do |bad|
        expect(described_class.resolve(bad)).to be_nil
      end
    end
  end
end
