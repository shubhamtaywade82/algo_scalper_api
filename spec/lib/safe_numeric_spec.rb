# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SafeNumeric do
  describe '.to_non_negative_integer' do
    it 'returns 0 for nil' do
      expect(described_class.to_non_negative_integer(nil)).to eq(0)
    end

    it 'returns integers unchanged when non-negative' do
      expect(described_class.to_non_negative_integer(42)).to eq(42)
    end

    it 'clamps negative integers to 0' do
      expect(described_class.to_non_negative_integer(-3)).to eq(0)
    end

    it 'truncates finite floats toward zero' do
      expect(described_class.to_non_negative_integer(9.9)).to eq(9)
    end

    it 'returns 0 for NaN' do
      expect(described_class.to_non_negative_integer(Float::NAN)).to eq(0)
    end

    it 'returns 0 for positive infinity' do
      expect(described_class.to_non_negative_integer(Float::INFINITY)).to eq(0)
    end

    it 'returns 0 for BigDecimal NaN' do
      expect(described_class.to_non_negative_integer(BigDecimal('NaN'))).to eq(0)
    end
  end
end
